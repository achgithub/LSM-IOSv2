import Foundation

/// Error thrown by the not-yet-implemented v2 cloud surface.
struct CloudError: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
    static let notImplemented = CloudError(message: "v2 skeleton — not implemented")
}

/// Cloud-backed game state client (NEW in v2) — **skeleton**.
///
/// This is the per-game/per-player surface that v1 never had (v1 kept all game
/// state on-device). It talks to the LSM v2 Worker's Layer-2 routes — `/games`
/// and `/games/:id/...` for the manager, plus the submission-queue endpoints —
/// where the source of truth is a regional-shard D1, not SwiftData.
///
/// The existing read-only sports-data calls (teams/fixtures/standings) still live
/// alongside in `APIClient` / `LeagueData`; this client is purely the new layer.
/// The shard base URL must be resolved per league via a league→shard manifest
/// mirroring `worker/src/shards.ts`. See docs/lsm-v2-architecture.md §2 and
/// worker/src/routes/games.ts.
enum GameCloudClient {
    // MARK: Games / players (manager-facing)
    static func createGame(mode: GameMode, leagueID: String, name: String) async throws -> Never {
        throw CloudError.notImplemented
    }

    static func listGames() async throws -> Never {
        throw CloudError.notImplemented
    }

    // MARK: Picks (LMS) / predictions (Predictor) — manager write-through
    static func submitManagerPick() async throws -> Never {
        throw CloudError.notImplemented
    }

    static func submitManagerPrediction() async throws -> Never {
        throw CloudError.notImplemented
    }

    // MARK: Submission queue (approve/reject) — see SubmissionQueueView
    static func pendingSubmissions(gameID: String) async throws -> Never {
        throw CloudError.notImplemented
    }

    static func decide(submissionID: String, approve: Bool) async throws -> Never {
        throw CloudError.notImplemented
    }
}
