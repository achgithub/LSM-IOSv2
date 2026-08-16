import Foundation
import SwiftData

/// Builds a local `Game`/`Round`/`Player`/`Pick`/`Prediction`/`KillerPrediction`
/// graph from a `GameSyncBundle` pulled via `GameSyncClient`.
///
/// Deliberately **not** modeled on `GameTransfer.swift`, despite the shape
/// overlap — that importer's whole contract is "a copy, never a merge": it
/// mints fresh UUIDs throughout and explicitly drops `cloudGameTokenRaw`
/// ("PWA links never transfer"). Sync is the opposite — it's the *same*
/// game continuing on a new device, so identity has to be preserved:
///   - `Game.cloudGameTokenRaw` is set to the real `gameToken`, not left nil
///     — otherwise the reconstructed game is cloud-dead (no further pushes,
///     no approval queue, no re-sync).
///   - Each `Player.id` is set to the bundle's `localPlayerId`, not a fresh
///     UUID — that's the literal value `game_enrollments.local_player_id`
///     already holds server-side, so existing PWA player links keep
///     resolving to the right player after sync.
enum GameSyncBuilder {
    enum BuildError: LocalizedError {
        case invalidConfig
        case alreadySynced

        var errorDescription: String? {
            switch self {
            case .invalidConfig:
                return AppString("This game's settings couldn't be read. Try syncing again.")
            case .alreadySynced:
                return AppString("This game is already on this device.")
            }
        }
    }

    /// Only the current open round is ever reconstructed with real fixtures
    /// — `round_pushes` is overwrite-in-place server-side, so no fixture
    /// history is recoverable regardless of what this builder does.
    /// Player status/standings are derived from the *full* results history
    /// (LMS elimination, Killer lives/hits/correct-predictions, Predictor's
    /// running `cumulativePoints`), since `round_results` does keep one row
    /// per round — but none of it is replayed as fake historical `Round`/
    /// `Prediction` rows. Predictor's total instead lands in
    /// `Player.carriedOverPoints`, added to the live sum by
    /// `PredictorStandings.rows(for:)` — see that field's doc comment for
    /// why (no fabricated Round leaking into fixture/history UI).
    @discardableResult
    static func build(from bundle: GameSyncBundle, gameToken: String, into context: ModelContext) throws -> Game {
        guard bundle.syncable, let configJson = bundle.gameConfigJson,
              let configData = configJson.data(using: .utf8),
              let config = try? JSONDecoder().decode(GameConfigPayload.self, from: configData),
              let mode = GameMode(rawValue: config.modeRaw)
        else { throw BuildError.invalidConfig }

        let normalizedToken = gameToken.lowercased()
        let existingGames = (try? context.fetch(FetchDescriptor<Game>())) ?? []
        guard !existingGames.contains(where: { $0.cloudGameTokenRaw == normalizedToken }) else {
            throw BuildError.alreadySynced
        }

        let game = Game(
            name: bundle.currentRound.gameName ?? AppString("Synced Game"),
            season: config.season,
            allowRepeats: config.allowRepeats,
            anonymityMode: AnonymityMode(rawValue: config.anonymityModeRaw) ?? .named,
            leagueIds: config.leagueIdsRaw,
            drawEliminates: config.drawEliminates,
            postponedEliminates: config.postponedEliminates,
            isDemoData: false,
            mode: mode,
            predictorExactPoints: config.predictorExactPoints,
            predictorGDEnabled: config.predictorGDEnabled,
            predictorGDPoints: config.predictorGDPoints,
            predictorResultEnabled: config.predictorResultEnabled,
            predictorResultPoints: config.predictorResultPoints,
            predictorJokerEnabled: config.predictorJokerEnabled,
            killerBuildPhaseRounds: config.killerBuildPhaseRounds,
            killerMaxAdditionalLives: config.killerMaxAdditionalLives,
            killerMaxMPG: config.killerMaxMPG
        )
        game.statusRaw = GameStatus.active.rawValue
        game.cloudGameTokenRaw = normalizedToken
        // The bundle's players[] already reflects a completed enrollment
        // server-side (that's how we have localPlayerIds to restore) — no
        // further roster push is needed before this game can be used.
        game.cloudRosterEnrolled = true
        context.insert(game)

        let existingMembers = (try? context.fetch(FetchDescriptor<RosterMember>())) ?? []
        var membersByName = Dictionary(
            existingMembers.map { ($0.name.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var playersByLocalId: [String: Player] = [:]
        var playersByToken: [String: Player] = [:]
        for p in bundle.players {
            let player = Player(name: p.playerName, game: game, isManager: false, entryNumber: game.nextEntryNumber)
            if let uuid = UUID(uuidString: p.localPlayerId) {
                player.id = uuid
            }
            let key = p.playerName.lowercased()
            let rosterMember: RosterMember
            if let existing = membersByName[key] {
                rosterMember = existing
            } else {
                rosterMember = RosterMember(name: p.playerName)
                context.insert(rosterMember)
                membersByName[key] = rosterMember
            }
            player.rosterMemberId = rosterMember.id
            context.insert(player)
            game.players.append(player)
            playersByLocalId[p.localPlayerId.lowercased()] = player
            playersByToken[p.token.lowercased()] = player

            if mode == .killer {
                let state = KillerPlayerState(player: player, game: game)
                context.insert(state)
                player.killerState = state
            }
        }

        applyResultsHistory(bundle.results, mode: mode, playersByLocalId: playersByLocalId)

        let round = Round(
            roundNumber: bundle.currentRound.roundNumber,
            deadline: parseDate(bundle.currentRound.deadline) ?? Date(),
            fixtureIds: fixtureIds(from: bundle.currentRound.fixturesJson),
            roundType: .normal,
            game: game
        )
        round.statusRaw = RoundStatus.open.rawValue
        context.insert(round)
        game.rounds.append(round)

        applyApprovedSubmissions(bundle.approvedSubmissions, mode: mode, round: round, playersByToken: playersByToken, context: context)

        return game
    }

    // MARK: - Results history → player status

    private struct LMSResultItem: Decodable { let playerId: String; let survived: Bool }
    private struct KillerResultItem: Decodable {
        let playerId: String; let lives: Int; let eliminated: Bool
        let hitsLandedThisRound: Int; let correctPredictionsThisRound: Int
    }
    private struct PredictorResultItem: Decodable {
        let playerId: String; let cumulativePoints: Int
    }

    private static func applyResultsHistory(
        _ results: [GameSyncBundle.ResultEntry], mode: GameMode, playersByLocalId: [String: Player]
    ) {
        switch mode {
        case .lms:
            // Elimination is terminal, so folding every round in order
            // (server returns them ascending by round_number) and letting a
            // later "eliminated" win is correct regardless of scan order.
            for entry in results {
                guard let data = entry.resultsJson.data(using: .utf8),
                      let items = try? JSONDecoder().decode([LMSResultItem].self, from: data) else { continue }
                for item in items where !item.survived {
                    playersByLocalId[item.playerId.lowercased()]?.status = .eliminated
                }
            }

        case .killer:
            // `lives`/`eliminated` are current-as-of-that-round values (use
            // the latest); hits/correct-predictions are per-round deltas on
            // the wire (see PWARoundPusher.killerPreviousResults), so the
            // cumulative KillerPlayerState totals need summing across every
            // round, not just reading the last one.
            var latestLives: [String: Int] = [:]
            var latestEliminated: [String: Bool] = [:]
            var totalHits: [String: Int] = [:]
            var totalCorrect: [String: Int] = [:]
            for entry in results {
                guard let data = entry.resultsJson.data(using: .utf8),
                      let items = try? JSONDecoder().decode([KillerResultItem].self, from: data) else { continue }
                for item in items {
                    let key = item.playerId.lowercased()
                    latestLives[key] = item.lives
                    latestEliminated[key] = item.eliminated
                    totalHits[key, default: 0] += item.hitsLandedThisRound
                    totalCorrect[key, default: 0] += item.correctPredictionsThisRound
                }
            }
            for (key, player) in playersByLocalId {
                guard let state = player.killerState else { continue }
                if let lives = latestLives[key] { state.lives = lives }
                if latestEliminated[key] == true { player.status = .eliminated }
                state.successfulHitsLanded = totalHits[key] ?? 0
                state.correctPredictions = totalCorrect[key] ?? 0
            }

        case .predictor:
            // No fake Round/Prediction rows — see Player.carriedOverPoints's
            // doc comment. `cumulativePoints` is already a running total as
            // of that round, so only the latest entry per player is needed
            // (not summed, unlike Killer's per-round deltas above).
            for entry in results {
                guard let data = entry.resultsJson.data(using: .utf8),
                      let items = try? JSONDecoder().decode([PredictorResultItem].self, from: data) else { continue }
                for item in items {
                    playersByLocalId[item.playerId.lowercased()]?.carriedOverPoints = item.cumulativePoints
                }
            }
        }
    }

    // MARK: - Approved submissions → current-round Pick/Prediction/KillerPrediction

    private static func applyApprovedSubmissions(
        _ submissions: [GameSyncBundle.ApprovedSubmission], mode: GameMode, round: Round,
        playersByToken: [String: Player], context: ModelContext
    ) {
        let decoder = JSONDecoder()
        for submission in submissions {
            guard let player = playersByToken[submission.token.lowercased()],
                  let data = submission.payloadJson.data(using: .utf8),
                  let payload = try? decoder.decode(SubmissionPayload.self, from: data)
            else { continue }

            switch mode {
            case .lms:
                guard let teamId = payload.teamId else { continue }
                let pick = Pick(teamId: teamId, fixtureId: payload.fixtureId, player: player, round: round)
                context.insert(pick)
                round.picks.append(pick)

            case .predictor:
                for score in payload.scores ?? [] {
                    let prediction = Prediction(
                        fixtureId: score.fixtureId, predictedHome: score.home, predictedAway: score.away,
                        isJoker: score.isJoker ?? false, player: player, round: round
                    )
                    context.insert(prediction)
                    round.predictions.append(prediction)
                }

            case .killer:
                for outcome in payload.outcomes ?? [] {
                    let prediction = KillerPrediction(
                        fixtureId: outcome.fixtureId,
                        predictedOutcome: FixtureOutcome(rawValue: outcome.outcome) ?? .homeWin,
                        hitTargetPlayerId: outcome.hitTargetId.flatMap { UUID(uuidString: $0) },
                        player: player, round: round
                    )
                    context.insert(prediction)
                    round.killerPredictions.append(prediction)
                }
            }
        }
    }

    // MARK: - Small parsing helpers

    private struct FixtureRef: Decodable { let fixtureId: Int }

    private static func fixtureIds(from fixturesJson: String) -> [Int] {
        guard let data = fixturesJson.data(using: .utf8),
              let items = try? JSONDecoder().decode([FixtureRef].self, from: data) else { return [] }
        return items.map(\.fixtureId)
    }

    /// The server emits `Date.toISOString()` (fractional seconds) — mirrors
    /// `AppAttestService.parseExpiry`'s fallback, duplicated locally rather
    /// than shared since it's a three-line utility, not worth coupling this
    /// file to that one over.
    private static func parseDate(_ string: String?) -> Date? {
        guard let string else { return nil }
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFractional.date(from: string) { return date }
        return ISO8601DateFormatter().date(from: string)
    }
}
