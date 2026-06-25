import Foundation
import SwiftData

/// A complete, self-contained snapshot of one `Game` and everything under it
/// (players, rounds, picks, predictions) — mode-agnostic by design (§0): LMS
/// and Predictor games both serialize through the same shape, since `Game`
/// carries its own `mode`. This is the one blob shape Cloud Backup serializes
/// to R2; restoring deserializes it back into fresh SwiftData rows.
///
/// IDs in a snapshot are the *original* on-device UUIDs, used only to wire up
/// relationships within the snapshot (player→game, pick→player/round, etc).
/// Restoring always mints brand-new UUIDs for the inserted rows — a restore
/// is a copy, not a merge, so it must never collide with a `@Attribute(.unique)`
/// id already on the device (e.g. restoring onto a phone that already has
/// other games, or restoring the same backup twice).
struct GameSnapshot: Codable {
    let id: UUID
    let name: String
    let season: String
    let statusRaw: String
    let allowRepeats: Bool
    let anonymityModeRaw: String
    let drawEliminates: Bool
    let postponedEliminates: Bool
    let lastOutcomeRaw: String?
    let createdAt: Date
    let isDemoData: Bool
    let leagueIdsRaw: [String]
    let modeRaw: String
    let predictorExactPoints: Int
    let predictorGDEnabled: Bool
    let predictorGDPoints: Int
    let predictorResultEnabled: Bool
    let predictorResultPoints: Int
    let predictorJokerEnabled: Bool
    let players: [PlayerSnapshot]
    let rounds: [RoundSnapshot]

    struct PlayerSnapshot: Codable {
        let id: UUID
        let name: String
        let statusRaw: String
        let entryNumber: Int
        let teamPoolResetAfterRound: Int
        let isManager: Bool
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
    }

    struct PickSnapshot: Codable {
        let teamId: Int
        let resultRaw: String?
        /// References `PlayerSnapshot.id` within the same `GameSnapshot`.
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
        /// References `PlayerSnapshot.id` within the same `GameSnapshot`.
        let playerId: UUID
    }
}

/// One or more games, the unit a Cloud Backup blob actually stores ("game(s)"
/// per §0) — a manager may have several games on-device, of either mode,
/// backed up together in one bundle.
struct BackupBundle: Codable {
    let games: [GameSnapshot]
}

enum GameSnapshotBuilder {
    /// Serialize a live `Game` (and everything under it) into a snapshot.
    static func snapshot(of game: Game) -> GameSnapshot {
        GameSnapshot(
            id: game.id,
            name: game.name,
            season: game.season,
            statusRaw: game.statusRaw,
            allowRepeats: game.allowRepeats,
            anonymityModeRaw: game.anonymityModeRaw,
            drawEliminates: game.drawEliminates,
            postponedEliminates: game.postponedEliminates,
            lastOutcomeRaw: game.lastOutcomeRaw,
            createdAt: game.createdAt,
            isDemoData: game.isDemoData,
            leagueIdsRaw: game.leagueIdsRaw,
            modeRaw: game.modeRaw,
            predictorExactPoints: game.predictorExactPoints,
            predictorGDEnabled: game.predictorGDEnabled,
            predictorGDPoints: game.predictorGDPoints,
            predictorResultEnabled: game.predictorResultEnabled,
            predictorResultPoints: game.predictorResultPoints,
            predictorJokerEnabled: game.predictorJokerEnabled,
            players: game.players.map { player in
                GameSnapshot.PlayerSnapshot(
                    id: player.id,
                    name: player.name,
                    statusRaw: player.statusRaw,
                    entryNumber: player.entryNumber,
                    teamPoolResetAfterRound: player.teamPoolResetAfterRound,
                    isManager: player.isManager
                )
            },
            rounds: game.rounds.map { round in
                GameSnapshot.RoundSnapshot(
                    id: round.id,
                    roundNumber: round.roundNumber,
                    roundTypeRaw: round.roundTypeRaw,
                    fixtureIds: round.fixtureIds,
                    deadline: round.deadline,
                    statusRaw: round.statusRaw,
                    picks: round.picks.compactMap { pick in
                        guard let playerId = pick.player?.id else { return nil }
                        return GameSnapshot.PickSnapshot(
                            teamId: pick.teamId, resultRaw: pick.resultRaw, playerId: playerId
                        )
                    },
                    predictions: round.predictions.compactMap { prediction in
                        guard let playerId = prediction.player?.id else { return nil }
                        return GameSnapshot.PredictionSnapshot(
                            fixtureId: prediction.fixtureId,
                            predictedHome: prediction.predictedHome,
                            predictedAway: prediction.predictedAway,
                            actualHome: prediction.actualHome,
                            actualAway: prediction.actualAway,
                            pointsAwarded: prediction.pointsAwarded,
                            isJoker: prediction.isJoker,
                            playerId: playerId
                        )
                    }
                )
            }
        )
    }

    /// Restore a snapshot into fresh SwiftData rows, inserted into `context`.
    /// Mints new UUIDs throughout (a restore is a copy, never a merge), using
    /// a per-call id map to keep the snapshot's internal player references
    /// wired to the newly-created `Player` rows.
    @discardableResult
    static func restore(_ snapshot: GameSnapshot, into context: ModelContext) -> Game {
        let game = Game(
            name: snapshot.name,
            season: snapshot.season,
            allowRepeats: snapshot.allowRepeats,
            leagueIds: snapshot.leagueIdsRaw,
            drawEliminates: snapshot.drawEliminates,
            postponedEliminates: snapshot.postponedEliminates,
            isDemoData: snapshot.isDemoData,
            mode: GameMode(rawValue: snapshot.modeRaw) ?? .lms,
            predictorExactPoints: snapshot.predictorExactPoints,
            predictorGDEnabled: snapshot.predictorGDEnabled,
            predictorGDPoints: snapshot.predictorGDPoints,
            predictorResultEnabled: snapshot.predictorResultEnabled,
            predictorResultPoints: snapshot.predictorResultPoints,
            predictorJokerEnabled: snapshot.predictorJokerEnabled
        )
        game.statusRaw = snapshot.statusRaw
        game.anonymityModeRaw = snapshot.anonymityModeRaw
        game.lastOutcomeRaw = snapshot.lastOutcomeRaw
        game.createdAt = snapshot.createdAt
        context.insert(game)

        var newPlayerId: [UUID: Player] = [:]
        for p in snapshot.players {
            let player = Player(name: p.name, game: game, isManager: p.isManager, entryNumber: p.entryNumber)
            player.statusRaw = p.statusRaw
            player.teamPoolResetAfterRound = p.teamPoolResetAfterRound
            context.insert(player)
            game.players.append(player)
            newPlayerId[p.id] = player
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
                let pick = Pick(teamId: pk.teamId, player: player, round: round)
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
        }

        return game
    }
}
