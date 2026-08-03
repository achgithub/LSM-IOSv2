import Foundation
import SwiftData

/// Writes/reads a `GameTransferSnapshot` as JSON on disk — mirrors
/// `GameExportFiles`'s safe-filename + temp-file pattern.
enum GameTransferFile {
    enum TransferError: Error { case writeFailed, readFailed }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    @discardableResult
    static func write(snapshot: GameTransferSnapshot, gameName: String) throws -> URL {
        let illegalCharacters = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let safeName = gameName
            .components(separatedBy: illegalCharacters)
            .joined()
            .trimmingCharacters(in: .whitespaces)
        let base = safeName.isEmpty ? "Game" : safeName
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(base) - transfer.json")
        do {
            let data = try encoder.encode(snapshot)
            try data.write(to: url, options: .atomic)
        } catch {
            throw TransferError.writeFailed
        }
        return url
    }

    static func read(from url: URL) throws -> GameTransferSnapshot {
        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode(GameTransferSnapshot.self, from: data)
        } catch {
            throw TransferError.readFailed
        }
    }
}

/// A complete, self-contained snapshot of one `Game` and everything under it
/// (players, rounds, picks/predictions), for handing a running game to
/// another manager's device — they export, send the file, the receiving
/// manager imports and continues running it. Mode-agnostic by design: LMS,
/// Predictor, and Killer games all serialize through the same shape, since
/// `Game` carries its own `mode`.
///
/// Adapted from the deleted Cloud Backup feature's `GameSnapshot`/
/// `GameSnapshotBuilder` (`git show fa0b576^:.../Core/Backup/GameSnapshot.swift`)
/// — same id-remapping mechanism, without the whole-device `BackupBundle`/
/// roster/managerToken wrapper this doesn't need (this is one game, between
/// two independent managers, not a self-restore), without the dead
/// `predictorPublish*`/`cloudGameTokenRaw` fields, and with `Pick.fixtureId`
/// added (didn't exist on `Pick` when the old snapshot was written).
///
/// IDs in a snapshot are the *original* on-device UUIDs, used only to wire up
/// relationships within the snapshot (pick→player, killer hit-target→player,
/// etc). Importing always mints brand-new UUIDs — an import is a copy, never
/// a merge, so it must never collide with a `@Attribute(.unique)` id already
/// on the receiving device.
struct GameTransferSnapshot: Codable {
    let name: String
    let season: String
    let statusRaw: String
    let allowRepeats: Bool
    let anonymityModeRaw: String
    let drawEliminates: Bool
    let postponedEliminates: Bool
    let lastOutcomeRaw: String?
    let createdAt: Date
    let leagueIdsRaw: [String]
    let modeRaw: String
    let predictorExactPoints: Int
    let predictorGDEnabled: Bool
    let predictorGDPoints: Int
    let predictorResultEnabled: Bool
    let predictorResultPoints: Int
    let predictorJokerEnabled: Bool
    let killerBuildPhaseRounds: Int
    let killerMaxAdditionalLives: Int
    let killerMaxMPG: Int
    let players: [PlayerSnapshot]
    let rounds: [RoundSnapshot]

    struct PlayerSnapshot: Codable {
        let id: UUID
        let name: String
        let statusRaw: String
        let entryNumber: Int
        let teamPoolResetAfterRound: Int
        /// Read but ignored on import — the receiving manager is a
        /// different person; every imported player becomes a regular
        /// (non-manager) player. They decide separately whether to add
        /// themselves via "Add Players."
        let isManager: Bool
        /// Nil for non-Killer games.
        let killerState: KillerPlayerStateSnapshot?
    }

    struct KillerPlayerStateSnapshot: Codable {
        let lives: Int
        let additionalLivesGained: Int
        let correctPredictions: Int
        let successfulHitsLanded: Int
    }

    struct RoundSnapshot: Codable {
        let id: UUID
        let roundNumber: Int
        let roundTypeRaw: String
        let fixtureIds: [Int]
        let deadline: Date
        let statusRaw: String
        let picks: [PickSnapshot]
        let predictions: [PredictionSnapshot]
        let killerPredictions: [KillerPredictionSnapshot]
    }

    struct PickSnapshot: Codable {
        let teamId: Int
        let fixtureId: Int?
        let resultRaw: String?
        /// References `PlayerSnapshot.id` within the same snapshot.
        let playerId: UUID
    }

    struct PredictionSnapshot: Codable {
        let fixtureId: Int
        let predictedHome: Int
        let predictedAway: Int
        let actualHome: Int?
        let actualAway: Int?
        let pointsAwarded: Int?
        let isJoker: Bool
        /// References `PlayerSnapshot.id` within the same snapshot.
        let playerId: UUID
    }

    struct KillerPredictionSnapshot: Codable {
        let fixtureId: Int
        let predictedOutcomeRaw: String
        let actualOutcomeRaw: String?
        let wasCorrect: Bool?
        /// References another `PlayerSnapshot.id` within the same snapshot —
        /// remapped through the id table at import time, same as `playerId`.
        let hitTargetPlayerId: UUID?
        let hitLanded: Bool?
        /// References `PlayerSnapshot.id` within the same snapshot.
        let playerId: UUID
    }
}

enum GameTransferBuilder {
    /// Serialize a live `Game` (and everything under it) into a snapshot.
    static func snapshot(of game: Game) -> GameTransferSnapshot {
        GameTransferSnapshot(
            name: game.name,
            season: game.season,
            statusRaw: game.statusRaw,
            allowRepeats: game.allowRepeats,
            anonymityModeRaw: game.anonymityModeRaw,
            drawEliminates: game.drawEliminates,
            postponedEliminates: game.postponedEliminates,
            lastOutcomeRaw: game.lastOutcomeRaw,
            createdAt: game.createdAt,
            leagueIdsRaw: game.leagueIdsRaw,
            modeRaw: game.modeRaw,
            predictorExactPoints: game.predictorExactPoints,
            predictorGDEnabled: game.predictorGDEnabled,
            predictorGDPoints: game.predictorGDPoints,
            predictorResultEnabled: game.predictorResultEnabled,
            predictorResultPoints: game.predictorResultPoints,
            predictorJokerEnabled: game.predictorJokerEnabled,
            killerBuildPhaseRounds: game.killerBuildPhaseRounds,
            killerMaxAdditionalLives: game.killerMaxAdditionalLives,
            killerMaxMPG: game.killerMaxMPG,
            players: game.players.map { player in
                GameTransferSnapshot.PlayerSnapshot(
                    id: player.id,
                    name: player.name,
                    statusRaw: player.statusRaw,
                    entryNumber: player.entryNumber,
                    teamPoolResetAfterRound: player.teamPoolResetAfterRound,
                    isManager: player.isManager,
                    killerState: player.killerState.map { state in
                        GameTransferSnapshot.KillerPlayerStateSnapshot(
                            lives: state.lives,
                            additionalLivesGained: state.additionalLivesGained,
                            correctPredictions: state.correctPredictions,
                            successfulHitsLanded: state.successfulHitsLanded
                        )
                    }
                )
            },
            rounds: game.rounds.map { round in
                GameTransferSnapshot.RoundSnapshot(
                    id: round.id,
                    roundNumber: round.roundNumber,
                    roundTypeRaw: round.roundTypeRaw,
                    fixtureIds: round.fixtureIds,
                    deadline: round.deadline,
                    statusRaw: round.statusRaw,
                    picks: round.picks.compactMap { pick in
                        guard let playerId = pick.player?.id else { return nil }
                        return GameTransferSnapshot.PickSnapshot(
                            teamId: pick.teamId, fixtureId: pick.fixtureId,
                            resultRaw: pick.resultRaw, playerId: playerId
                        )
                    },
                    predictions: round.predictions.compactMap { prediction in
                        guard let playerId = prediction.player?.id else { return nil }
                        return GameTransferSnapshot.PredictionSnapshot(
                            fixtureId: prediction.fixtureId,
                            predictedHome: prediction.predictedHome,
                            predictedAway: prediction.predictedAway,
                            actualHome: prediction.actualHome,
                            actualAway: prediction.actualAway,
                            pointsAwarded: prediction.pointsAwarded,
                            isJoker: prediction.isJoker,
                            playerId: playerId
                        )
                    },
                    killerPredictions: round.killerPredictions.compactMap { prediction in
                        guard let playerId = prediction.player?.id else { return nil }
                        return GameTransferSnapshot.KillerPredictionSnapshot(
                            fixtureId: prediction.fixtureId,
                            predictedOutcomeRaw: prediction.predictedOutcomeRaw,
                            actualOutcomeRaw: prediction.actualOutcomeRaw,
                            wasCorrect: prediction.wasCorrect,
                            hitTargetPlayerId: prediction.hitTargetPlayerId,
                            hitLanded: prediction.hitLanded,
                            playerId: playerId
                        )
                    }
                )
            }
        )
    }

    /// Import a snapshot into fresh SwiftData rows, inserted into `context`.
    /// Mints new UUIDs throughout, using a per-call id map to keep the
    /// snapshot's internal player references (including
    /// `KillerPrediction.hitTargetPlayerId`) wired to the newly-created
    /// `Player` rows.
    ///
    /// `nameOverrides` (keyed by the snapshot's *original* `PlayerSnapshot.id`)
    /// is how the caller's conflict-resolution UI supplies a renamed player
    /// name once it's been resolved against the receiving device's roster —
    /// this function doesn't detect conflicts itself, only applies the
    /// caller's decision, and always finds-or-creates a `RosterMember` by
    /// the final name so the import actually populates the roster, not just
    /// this one game.
    @discardableResult
    static func restore(
        _ snapshot: GameTransferSnapshot,
        nameOverrides: [UUID: String] = [:],
        into context: ModelContext
    ) -> Game {
        let game = Game(
            name: snapshot.name,
            season: snapshot.season,
            allowRepeats: snapshot.allowRepeats,
            leagueIds: snapshot.leagueIdsRaw,
            drawEliminates: snapshot.drawEliminates,
            postponedEliminates: snapshot.postponedEliminates,
            isDemoData: false,
            mode: GameMode(rawValue: snapshot.modeRaw) ?? .lms,
            predictorExactPoints: snapshot.predictorExactPoints,
            predictorGDEnabled: snapshot.predictorGDEnabled,
            predictorGDPoints: snapshot.predictorGDPoints,
            predictorResultEnabled: snapshot.predictorResultEnabled,
            predictorResultPoints: snapshot.predictorResultPoints,
            predictorJokerEnabled: snapshot.predictorJokerEnabled,
            killerBuildPhaseRounds: snapshot.killerBuildPhaseRounds,
            killerMaxAdditionalLives: snapshot.killerMaxAdditionalLives,
            killerMaxMPG: snapshot.killerMaxMPG
        )
        game.statusRaw = snapshot.statusRaw
        game.anonymityModeRaw = snapshot.anonymityModeRaw
        game.lastOutcomeRaw = snapshot.lastOutcomeRaw
        game.createdAt = snapshot.createdAt
        // cloudGameTokenRaw stays nil — PWA links never transfer; a fresh
        // mint is needed on the receiving device if PWA is used later.
        context.insert(game)

        let existingMembers = (try? context.fetch(FetchDescriptor<RosterMember>())) ?? []
        var membersByName = Dictionary(
            existingMembers.map { ($0.name.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var newPlayerId: [UUID: Player] = [:]
        for p in snapshot.players {
            let finalName = nameOverrides[p.id] ?? p.name
            let player = Player(name: finalName, game: game, isManager: false, entryNumber: p.entryNumber)
            player.statusRaw = p.statusRaw
            player.teamPoolResetAfterRound = p.teamPoolResetAfterRound

            let key = finalName.lowercased()
            let rosterMember: RosterMember
            if let existing = membersByName[key] {
                rosterMember = existing
            } else {
                rosterMember = RosterMember(name: finalName)
                context.insert(rosterMember)
                membersByName[key] = rosterMember
            }
            player.rosterMemberId = rosterMember.id

            context.insert(player)
            game.players.append(player)
            newPlayerId[p.id] = player

            if let ks = p.killerState {
                let state = KillerPlayerState(player: player, game: game)
                state.lives = ks.lives
                state.additionalLivesGained = ks.additionalLivesGained
                state.correctPredictions = ks.correctPredictions
                state.successfulHitsLanded = ks.successfulHitsLanded
                context.insert(state)
                player.killerState = state
            }
        }

        for r in snapshot.rounds {
            let round = Round(
                roundNumber: r.roundNumber,
                deadline: r.deadline,
                fixtureIds: r.fixtureIds,
                roundType: RoundType(rawValue: r.roundTypeRaw) ?? .normal,
                game: game
            )
            round.statusRaw = r.statusRaw
            context.insert(round)
            game.rounds.append(round)

            for pk in r.picks {
                guard let player = newPlayerId[pk.playerId] else { continue }
                let pick = Pick(teamId: pk.teamId, fixtureId: pk.fixtureId, player: player, round: round)
                pick.resultRaw = pk.resultRaw
                context.insert(pick)
                round.picks.append(pick)
            }

            for pr in r.predictions {
                guard let player = newPlayerId[pr.playerId] else { continue }
                let prediction = Prediction(
                    fixtureId: pr.fixtureId,
                    predictedHome: pr.predictedHome,
                    predictedAway: pr.predictedAway,
                    isJoker: pr.isJoker,
                    player: player,
                    round: round
                )
                prediction.actualHome = pr.actualHome
                prediction.actualAway = pr.actualAway
                prediction.pointsAwarded = pr.pointsAwarded
                context.insert(prediction)
                round.predictions.append(prediction)
            }

            for kp in r.killerPredictions {
                guard let player = newPlayerId[kp.playerId] else { continue }
                let remappedTargetId = kp.hitTargetPlayerId.flatMap { newPlayerId[$0]?.id }
                let prediction = KillerPrediction(
                    fixtureId: kp.fixtureId,
                    predictedOutcome: FixtureOutcome(rawValue: kp.predictedOutcomeRaw) ?? .homeWin,
                    hitTargetPlayerId: remappedTargetId,
                    player: player,
                    round: round
                )
                prediction.actualOutcomeRaw = kp.actualOutcomeRaw
                prediction.wasCorrect = kp.wasCorrect
                prediction.hitLanded = kp.hitLanded
                context.insert(prediction)
                round.killerPredictions.append(prediction)
            }
        }

        return game
    }
}
