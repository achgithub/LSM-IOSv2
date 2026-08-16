import Foundation

/// Wire shape for GET /manager/games — one row per game this manager owns.
/// `nonisolated` for the same reason as `ManagerToken`/`ShardID`: this
/// project defaults every type to MainActor isolation, but this is decoded
/// inside the `GameSyncClient` actor below — left un-annotated, that's a
/// hard error under Swift 6's strict concurrency mode, not just a warning.
nonisolated struct RemoteGameSummary: Decodable, Identifiable {
    let gameToken: String
    let mode: String
    let gameName: String?
    let roundNumber: Int
    let deadline: String?
    let updatedAt: String
    var id: String { gameToken }
}

/// Wire shape for GET /manager/games/:gameToken/sync — see worker-api's
/// routes/manager.ts for the exact fields. Field names already match the
/// server's camelCase JSON keys, so no `keyDecodingStrategy` is needed.
/// `nonisolated` — see `RemoteGameSummary`'s doc comment above.
nonisolated struct GameSyncBundle: Decodable {
    struct CurrentRound: Decodable {
        let mode: String
        let roundNumber: Int
        let deadline: String?
        let gameName: String?
        let fixturesJson: String
        let jokerEnabled: Bool
        let extraJson: String?
        let updatedAt: String
    }
    struct ResultEntry: Decodable {
        let roundNumber: Int
        let mode: String
        let resultsJson: String
        let createdAt: String
    }
    struct PlayerEntry: Decodable {
        let token: String
        let playerName: String
        let localPlayerId: String
        let eligibleTeamIdsJson: String?
        let managerSuffix: String?
    }
    struct ApprovedSubmission: Decodable {
        let token: String
        let payloadJson: String
    }

    /// False when `gameConfigJson` is nil — a game pushed before
    /// `round_pushes.game_config_json` existed, whose owning device hasn't
    /// relaunched to run the one-time backfill yet (see
    /// `SyncCoordinator.backfillGameConfigIfNeeded`). Reconstructing without
    /// config would mean guessing at scoring-critical settings, so
    /// `pullGame` throws `.notSyncable` rather than returning a bundle the
    /// caller might try to build from anyway.
    let syncable: Bool
    let gameConfigJson: String?
    let currentRound: CurrentRound
    let results: [ResultEntry]
    let players: [PlayerEntry]
    let approvedSubmissions: [ApprovedSubmission]
}

enum GameSyncError: LocalizedError {
    case notSyncable
    case other(APIError)

    var errorDescription: String? {
        switch self {
        case .notSyncable:
            return AppString("This game isn't ready to sync yet. Open the app on the original device once, then try again.")
        case .other(let apiError):
            return apiError.errorDescription
        }
    }
}

/// Client for the per-game sync routes (/manager/games, /manager/games/:token/sync)
/// — pulls a manager's games and one game's current-round state down to a new
/// device. Separate from `AccountClient`: linking a device only recovers
/// identity (manager_token); pulling a game is always a second, explicit,
/// per-game step. See routes/account.ts and routes/manager.ts's header
/// comments on the authority worker for the full picture.
actor GameSyncClient {
    static let shared = GameSyncClient()

    func listGames() async throws -> [RemoteGameSummary] {
        struct Response: Decodable { let games: [RemoteGameSummary] }
        let req = try await request(path: "/manager/games", method: "GET")
        let data = try await send(req)
        return try JSONDecoder().decode(Response.self, from: data).games
    }

    func pullGame(gameToken: String) async throws -> GameSyncBundle {
        let req = try await request(path: "/manager/games/\(gameToken.lowercased())/sync", method: "GET")
        let data = try await send(req)
        let bundle = try JSONDecoder().decode(GameSyncBundle.self, from: data)
        guard bundle.syncable, bundle.gameConfigJson != nil else { throw GameSyncError.notSyncable }
        return bundle
    }

    // MARK: - Internals

    private func request(path: String, method: String) async throws -> URLRequest {
        let base = await AppAttestService.shared.authorityURL()
        guard let url = URL(string: path, relativeTo: base) else { throw APIError.badURL }
        var req = URLRequest(url: url)
        req.httpMethod = method
        for (field, value) in await AppAttestService.shared.authorizationHeaders() {
            req.setValue(value, forHTTPHeaderField: field)
        }
        req.setValue(ManagerToken.current, forHTTPHeaderField: "X-Manager-Token")
        return req
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            let body = String(data: data, encoding: .utf8)
            await DiagnosticLog.shared.log("non-HTTP response for \(request.url?.absoluteString ?? ""): \(body ?? "")", category: "gamesync")
            throw APIError.badStatus(-1, body: body)
        }
        guard (200..<300).contains(http.statusCode) else {
            try await MaintenanceCheck.check(status: http.statusCode, data: data)
            let body = String(data: data, encoding: .utf8)
            await DiagnosticLog.shared.log("\(http.statusCode) for \(request.url?.absoluteString ?? ""): \(body ?? "")", category: "gamesync")
            throw GameSyncError.other(APIError.badStatus(http.statusCode, body: body))
        }
        await MaintenanceState.shared.clear()
        return data
    }
}
