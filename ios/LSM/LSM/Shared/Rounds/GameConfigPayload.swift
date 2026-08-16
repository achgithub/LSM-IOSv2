import Foundation

/// The game's own settings — league ids, LMS rules, Predictor/Killer scoring
/// config — sent alongside every round push as an opaque JSON string
/// (`gameConfig` in the push body, stored server-side as
/// `round_pushes.game_config_json`). Needed for `GameSyncClient` to
/// reconstruct a working game on a different device; without it, a synced
/// game would have to guess at scoring-critical settings like
/// `drawEliminates` or Predictor's point values, which is worse than not
/// syncing at all — see the design discussion in the sync work.
///
/// Deliberately narrower than `GameTransferSnapshot`: only the config that's
/// actually needed to keep scoring correct going forward, not the game's
/// current status/name/createdAt (already carried elsewhere in the push, or
/// not needed to resume play).
struct GameConfigPayload: Codable {
    let leagueIdsRaw: [String]
    let season: String
    let allowRepeats: Bool
    let anonymityModeRaw: String
    let drawEliminates: Bool
    let postponedEliminates: Bool
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

    init(game: Game) {
        leagueIdsRaw = game.leagueIdsRaw
        season = game.season
        allowRepeats = game.allowRepeats
        anonymityModeRaw = game.anonymityModeRaw
        drawEliminates = game.drawEliminates
        postponedEliminates = game.postponedEliminates
        modeRaw = game.modeRaw
        predictorExactPoints = game.predictorExactPoints
        predictorGDEnabled = game.predictorGDEnabled
        predictorGDPoints = game.predictorGDPoints
        predictorResultEnabled = game.predictorResultEnabled
        predictorResultPoints = game.predictorResultPoints
        predictorJokerEnabled = game.predictorJokerEnabled
        killerBuildPhaseRounds = game.killerBuildPhaseRounds
        killerMaxAdditionalLives = game.killerMaxAdditionalLives
        killerMaxMPG = game.killerMaxMPG
    }

    /// Pre-serialized for `pushRound`'s `gameConfigJSON:` parameter — same
    /// opaque-JSON-string convention as `extra`/`previousResultsJSON`.
    static func json(for game: Game) -> String? {
        try? String(data: JSONEncoder().encode(GameConfigPayload(game: game)), encoding: .utf8)
    }
}
