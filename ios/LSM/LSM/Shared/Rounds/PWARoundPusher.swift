import Foundation
import SwiftData
import OSLog

private let pwaPushLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "lsm", category: "submissions")

/// Thrown by the guard clauses that used to fail silently — lets the manual
/// "Resend to Player App" button tell the user *why* nothing was sent,
/// instead of just doing nothing with no feedback.
enum PWAPushError: LocalizedError {
    case noLeagueData
    case noRound
    case noCloudToken

    var errorDescription: String? {
        switch self {
        case .noLeagueData: return AppString("Couldn't load league data.")
        case .noRound: return AppString("This game has no round to send.")
        case .noCloudToken: return AppString("This game isn't linked to the Player App yet.")
        }
    }
}

/// Central place for pushing PWA round state — used by all three triggers
/// (round-open, game-complete, manual "resend") across all three modes, not
/// just the round-open flow. Game-complete and manual-resend don't have a
/// live `LeagueData` cache the way `OpenRoundView`/`KillerOpenRoundView` do
/// while their sheet is open, so this loads fresh data itself; that also
/// means there's exactly one implementation per mode family of "how do we
/// build/send a PWA push," rather than duplicating it per trigger.
enum PWARoundPusher {
    // MARK: - LMS / Predictor

    /// `round` is the round to push as "current" — the newly-opened round for
    /// a round-open trigger, or `nil` for game-complete/manual-resend (falls
    /// back to whichever round is numerically last, open or closed, so a
    /// completed game keeps resending its final round's data unchanged).
    /// Always attempts to attach the most-recently-closed round's results,
    /// regardless of trigger — safe/idempotent to resend the same result twice.
    static func pushLMSOrPredictor(game: Game, round: Round?, managerName: String, context: ModelContext) async throws {
        guard let ld = try? await LeagueData.load(for: game.leagues) else { throw PWAPushError.noLeagueData }
        guard let targetRound = round ?? game.rounds.max(by: { $0.roundNumber < $1.roundNumber }) else {
            throw PWAPushError.noRound
        }

        let fixtureItems: [FixturePushItem] = targetRound.fixtureIds.compactMap { fid in
            guard let m = ld.matches.first(where: { $0.id == fid }) else { return nil }
            let home = ld.teamsById[m.homeTeamId]?.name ?? "Home"
            let away = ld.teamsById[m.awayTeamId]?.name ?? "Away"
            return FixturePushItem(fixtureId: fid, home: home, away: away, kickoff: m.kickoff)
        }

        if game.cloudGameTokenRaw == nil {
            game.cloudGameTokenRaw = UUID().uuidString.lowercased()
        }
        guard let gameToken = game.cloudGameToken else { throw PWAPushError.noCloudToken }

        let fixtureTeamRefs: [TeamRef] = targetRound.fixtureIds.flatMap { fid -> [TeamRef] in
            guard let m = ld.matches.first(where: { $0.id == fid }) else { return [] }
            let home = ld.teamsById[m.homeTeamId]
            let away = ld.teamsById[m.awayTeamId]
            var refs: [TeamRef] = []
            if let home {
                refs.append(TeamRef(id: home.externalId, name: home.name,
                                     position: ld.standingsByTeam[home.externalId]?.position,
                                     fixtureId: fid, opponentName: away?.name))
            }
            if let away {
                refs.append(TeamRef(id: away.externalId, name: away.name,
                                     position: ld.standingsByTeam[away.externalId]?.position,
                                     fixtureId: fid, opponentName: home?.name))
            }
            return refs
        }
        let standingsKnown = fixtureTeamRefs.contains { $0.position != nil }
        let allowRepeats = game.allowRepeats
        let mode = game.mode

        var playerTokenMap: [UUID: String] = [:]
        var playerNameMap: [UUID: String] = [:]
        for player in game.activePlayers where !player.isManager {
            let member: RosterMember?
            if let memberId = player.rosterMemberId {
                let fd = FetchDescriptor<RosterMember>(predicate: #Predicate { $0.id == memberId })
                member = (try? context.fetch(fd))?.first
            } else {
                let name = player.name
                let fd = FetchDescriptor<RosterMember>(predicate: #Predicate { $0.name == name })
                member = (try? context.fetch(fd))?.first
                if let m = member { player.rosterMemberId = m.id }
            }
            if let rawToken = member?.submissionTokenRaw {
                playerTokenMap[player.id] = rawToken.lowercased()
                playerNameMap[player.id] = member?.name ?? player.name
            }
        }

        let managerSuffix: String? = game.players.first(where: { $0.isManager }).map {
            String($0.id.uuidString.replacingOccurrences(of: "-", with: "").suffix(8)).lowercased()
        }
        let linkedPlayers = game.activePlayers.filter { !$0.isManager && playerTokenMap[$0.id] != nil }
        let trimmedManagerName: String? = {
            let n = managerName.trimmingCharacters(in: .whitespacesAndNewlines)
            return n.isEmpty ? nil : n
        }()

        var playerItems: [PlayerPushItem] = []
        for player in linkedPlayers {
            guard let token = playerTokenMap[player.id] else { continue }
            let eligibleTeams: [EligibleTeam]
            if mode == .lms {
                let used = GameLogicService.usedTeamIds(for: player)
                let ordered = GameEngine.orderedAvailableTeams(
                    fixtureTeams: fixtureTeamRefs, used: used, allowRepeats: allowRepeats, standingsKnown: standingsKnown
                )
                eligibleTeams = ordered.map {
                    EligibleTeam(id: $0.id, name: $0.name, fixtureId: $0.fixtureId, opponentName: $0.opponentName)
                }
            } else {
                eligibleTeams = fixtureTeamRefs.map {
                    EligibleTeam(id: $0.id, name: $0.name, fixtureId: $0.fixtureId, opponentName: $0.opponentName)
                }
            }
            playerItems.append(PlayerPushItem(
                token: token, localPlayerId: player.id.uuidString.lowercased(),
                playerName: playerNameMap[player.id], eligibleTeams: eligibleTeams.isEmpty ? nil : eligibleTeams
            ))
        }

        let (prevRoundNumber, prevResultsJSON) = lmsOrPredictorPreviousResults(game: game, mode: mode, data: ld)

        do {
            try await SubmissionsClient.shared.pushRound(
                gameToken: gameToken,
                mode: mode.rawValue,
                roundNumber: targetRound.roundNumber,
                deadline: targetRound.deadline,
                gameName: game.name,
                fixtures: fixtureItems,
                jokerEnabled: game.predictorJokerEnabled,
                managerSuffix: managerSuffix,
                managerName: trimmedManagerName,
                players: playerItems,
                previousResultsRoundNumber: prevRoundNumber,
                previousResultsJSON: prevResultsJSON
            )
        } catch {
            pwaPushLog.warning("Round push failed: \(error.localizedDescription)")
            throw error
        }
    }

    /// The most-recently-closed round's per-player outcome — survived/
    /// eliminated + team picked (LMS), or this-round + cumulative points and
    /// standing (Predictor). Reads current `player.status`/persisted
    /// `pointsAwarded`, which is safe precisely because this is only ever
    /// called at the next round-open or game-complete: no round can have
    /// closed in between, so nothing is stale.
    private static func lmsOrPredictorPreviousResults(game: Game, mode: GameMode, data: LeagueData) -> (Int?, String?) {
        guard let lastClosed = game.rounds.filter({ $0.status == .closed })
            .max(by: { $0.roundNumber < $1.roundNumber }) else { return (nil, nil) }

        switch mode {
        case .lms:
            struct Item: Encodable { let playerId: String; let teamPicked: String?; let survived: Bool }
            let items: [Item] = lastClosed.picks.compactMap { pick in
                guard let player = pick.player else { return nil }
                let teamName = data.teamsById[pick.teamId]?.shortName ?? data.teamsById[pick.teamId]?.name
                return Item(playerId: player.id.uuidString.lowercased(), teamPicked: teamName, survived: player.status != .eliminated)
            }
            guard !items.isEmpty, let json = try? String(data: JSONEncoder().encode(items), encoding: .utf8) else { return (nil, nil) }
            return (lastClosed.roundNumber, json)

        case .predictor:
            struct Item: Encodable { let playerId: String; let pointsThisRound: Int; let cumulativePoints: Int; let position: Int }
            let pointsByPlayer = Dictionary(grouping: lastClosed.predictions, by: { $0.player?.id })
                .compactMapValues { predictions -> (Player, Int)? in
                    guard let player = predictions.first?.player else { return nil }
                    return (player, predictions.compactMap(\.pointsAwarded).reduce(0, +))
                }
            let standingsByPlayer = Dictionary(uniqueKeysWithValues: PredictorStandings.rows(for: game).map { ($0.player.id, $0) })
            let items: [Item] = pointsByPlayer.values.compactMap { player, pointsThisRound in
                guard let standing = standingsByPlayer[player.id] else { return nil }
                return Item(
                    playerId: player.id.uuidString.lowercased(), pointsThisRound: pointsThisRound,
                    cumulativePoints: standing.points, position: standing.position
                )
            }
            guard !items.isEmpty, let json = try? String(data: JSONEncoder().encode(items), encoding: .utf8) else { return (nil, nil) }
            return (lastClosed.roundNumber, json)

        case .killer:
            return (nil, nil)  // handled by pushKiller
        }
    }

    // MARK: - Killer

    /// Same shape as `pushLMSOrPredictor` but for Killer's phase/roster
    /// `extra` payload and its own per-player result fields (lives/hits
    /// rather than survived/points).
    static func pushKiller(game: Game, round: Round?, managerName: String, context: ModelContext) async throws {
        guard let ld = try? await LeagueData.load(for: game.leagues) else { throw PWAPushError.noLeagueData }
        guard let targetRound = round ?? game.rounds.max(by: { $0.roundNumber < $1.roundNumber }) else {
            throw PWAPushError.noRound
        }

        let fixtureItems: [FixturePushItem] = targetRound.fixtureIds.compactMap { fid in
            guard let m = ld.matches.first(where: { $0.id == fid }) else { return nil }
            let home = ld.teamsById[m.homeTeamId]?.name ?? "Home"
            let away = ld.teamsById[m.awayTeamId]?.name ?? "Away"
            return FixturePushItem(fixtureId: fid, home: home, away: away, kickoff: m.kickoff)
        }

        if game.cloudGameTokenRaw == nil {
            game.cloudGameTokenRaw = UUID().uuidString.lowercased()
        }
        guard let gameToken = game.cloudGameToken else { throw PWAPushError.noCloudToken }

        let phase = KillerScoringService.phase(for: targetRound, game: game)
        let extraJSON = killerExtraJSON(phase: phase, game: game)

        var playerTokenMap: [UUID: String] = [:]
        var playerNameMap: [UUID: String] = [:]
        for player in game.activePlayers where !player.isManager {
            let member: RosterMember?
            if let memberId = player.rosterMemberId {
                let fd = FetchDescriptor<RosterMember>(predicate: #Predicate { $0.id == memberId })
                member = (try? context.fetch(fd))?.first
            } else {
                let name = player.name
                let fd = FetchDescriptor<RosterMember>(predicate: #Predicate { $0.name == name })
                member = (try? context.fetch(fd))?.first
                if let m = member { player.rosterMemberId = m.id }
            }
            if let rawToken = member?.submissionTokenRaw {
                playerTokenMap[player.id] = rawToken.lowercased()
                playerNameMap[player.id] = member?.name ?? player.name
            }
        }

        let managerSuffix: String? = game.players.first(where: { $0.isManager }).map {
            String($0.id.uuidString.replacingOccurrences(of: "-", with: "").suffix(8)).lowercased()
        }
        let linkedPlayers = game.activePlayers.filter { !$0.isManager && playerTokenMap[$0.id] != nil }
        let trimmedManagerName: String? = {
            let n = managerName.trimmingCharacters(in: .whitespacesAndNewlines)
            return n.isEmpty ? nil : n
        }()

        let playerItems: [PlayerPushItem] = linkedPlayers.compactMap { player in
            guard let token = playerTokenMap[player.id] else { return nil }
            return PlayerPushItem(
                token: token, localPlayerId: player.id.uuidString.lowercased(),
                playerName: playerNameMap[player.id], eligibleTeams: nil
            )
        }

        let (prevRoundNumber, prevResultsJSON) = killerPreviousResults(game: game)

        do {
            try await SubmissionsClient.shared.pushRound(
                gameToken: gameToken,
                mode: game.mode.rawValue,
                roundNumber: targetRound.roundNumber,
                deadline: targetRound.deadline,
                gameName: game.name,
                fixtures: fixtureItems,
                jokerEnabled: false,
                managerSuffix: managerSuffix,
                managerName: trimmedManagerName,
                players: playerItems,
                extraJSON: extraJSON,
                previousResultsRoundNumber: prevRoundNumber,
                previousResultsJSON: prevResultsJSON
            )
        } catch {
            pwaPushLog.warning("Killer round push failed: \(error.localizedDescription)")
            throw error
        }
    }

    /// See `KillerOpenRoundView`'s original doc comment (now moved here): a
    /// `JSONEncoder`, not hand-built string interpolation — a player name
    /// containing a JSON-special character would otherwise produce invalid
    /// JSON. Kill Phase includes the full active-player roster.
    private static func killerExtraJSON(phase: KillerPhase, game: Game) -> String? {
        struct OtherPlayer: Encodable { let id: String; let name: String }
        struct Extra: Encodable { let phase: String; let otherPlayers: [OtherPlayer]? }

        let otherPlayers: [OtherPlayer]?
        if phase == .kill {
            otherPlayers = game.activePlayers
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                .map { OtherPlayer(id: $0.id.uuidString.lowercased(), name: $0.name) }
        } else {
            otherPlayers = nil
        }
        let extra = Extra(phase: phase == .build ? "build" : "kill", otherPlayers: otherPlayers)
        guard let data = try? JSONEncoder().encode(extra) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// The most-recently-closed round's per-player lives/hits outcome. Reads
    /// current `killerState.lives`/`player.status` and that round's
    /// persisted `killerPredictions` — safe for the same reason as the LMS/
    /// Predictor version above (only ever called right after that round, or
    /// at the next round-open, with nothing else able to have changed state
    /// in between).
    private static func killerPreviousResults(game: Game) -> (Int?, String?) {
        guard let lastClosed = game.rounds.filter({ $0.status == .closed })
            .max(by: { $0.roundNumber < $1.roundNumber }) else { return (nil, nil) }

        struct Item: Encodable {
            let playerId: String
            let lives: Int
            let eliminated: Bool
            let hitsLandedThisRound: Int
            let correctPredictionsThisRound: Int
        }

        let predictions = lastClosed.killerPredictions
        // Every player who either predicted this round or was someone's Hit
        // target — deduped by id (Player isn't guaranteed Hashable, so a
        // dictionary keyed on UUID rather than a Set).
        var relevantPlayerIds = Set(predictions.compactMap { $0.player?.id })
        relevantPlayerIds.formUnion(predictions.compactMap(\.hitTargetPlayerId))
        let playersById = Dictionary(uniqueKeysWithValues: game.players.map { ($0.id, $0) })

        let items: [Item] = relevantPlayerIds.compactMap { playerId -> Item? in
            guard let player = playersById[playerId], let state = player.killerState else { return nil }
            let hitsLanded = predictions.filter { $0.hitTargetPlayerId == player.id && $0.hitLanded == true }.count
            let correct = predictions.filter { $0.player?.id == player.id && $0.wasCorrect == true }.count
            return Item(
                playerId: player.id.uuidString.lowercased(),
                lives: state.lives,
                eliminated: player.status == .eliminated,
                hitsLandedThisRound: hitsLanded,
                correctPredictionsThisRound: correct
            )
        }
        guard !items.isEmpty, let json = try? String(data: JSONEncoder().encode(items), encoding: .utf8) else { return (nil, nil) }
        return (lastClosed.roundNumber, json)
    }
}
