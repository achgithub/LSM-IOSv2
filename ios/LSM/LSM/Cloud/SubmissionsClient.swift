import Foundation

/// Wire types for the Phase 5 submission queue Worker routes.

struct FixturePushItem: Encodable {
    let fixtureId: Int
    let home: String
    let away: String
    let kickoff: String
}

struct EligibleTeam: Encodable {
    let id: Int
    let name: String
    /// Which fixture this team occurrence belongs to, and its opponent's name
    /// — set when the team plays twice in the round so the PWA can show which
    /// match a pick is backing (mirrors `TeamRef.fixtureId`/`opponentName`).
    let fixtureId: Int?
    let opponentName: String?
}

struct PlayerPushItem: Encodable {
    let token: String
    let localPlayerId: String
    /// Current roster-member name, sent on every push so a rename made
    /// in-app rides along on the next round push and refreshes the
    /// backend's `player_tokens.player_name` without a dedicated call.
    let playerName: String?
    let eligibleTeams: [EligibleTeam]?
}

struct SubmissionItem: Decodable, Identifiable {
    let id: String
    let token: String
    let playerName: String
    let localPlayerId: String
    let managerSuffix: String?
    let roundNumber: Int
    let payload: SubmissionPayload
    let status: String
    let submittedAt: String
    let decidedAt: String?
}

struct SubmissionPayload: Decodable {
    // LMS
    let teamId: Int?
    let teamName: String?
    /// Which fixture this pick backs, when the team plays twice in the round.
    let fixtureId: Int?
    /// The opponent in that fixture, so the queue can show "Liverpool v Everton".
    let opponentName: String?
    // Predictor
    let scores: [PredictorScore]?
    // Killer
    let outcomes: [KillerOutcomeWire]?
}

struct PredictorScore: Decodable {
    let fixtureId: Int
    let home: Int
    let away: Int
    let isJoker: Bool?
}

struct KillerOutcomeWire: Decodable {
    let fixtureId: Int
    /// Raw `FixtureOutcome` rawValue string ("homeWin"/"draw"/"awayWin").
    let outcome: String
    /// Kill Phase only — nil in Build Phase. Local `Player` UUID string of
    /// the opponent this fixture's Hit targets.
    let hitTargetId: String?
}

struct ApproveResult: Decodable {
    let id: String
    let localPlayerId: String
    let managerSuffix: String?
    let roundNumber: Int
    let payload: SubmissionPayload
}

/// Client for the Phase 5 submission-queue Worker routes.
actor SubmissionsClient {
    static let shared = SubmissionsClient()

    static let playerBase = URL(string: "https://submit.sportsmanager.site")!

    static func playerLinkURL(token: String) -> URL {
        playerBase.appending(path: "s/\(token.lowercased())")
    }

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    // ── Manager-facing ────────────────────────────────────────────────────────

    func mintLink(playerName: String, managerName: String) async throws -> String {
        struct Body: Encodable { let playerName: String; let managerToken: String; let managerName: String }
        struct Response: Decodable { let token: String }
        var req = try await request(path: "/links", method: "POST")
        req.httpBody = try encoder.encode(Body(playerName: playerName, managerToken: ManagerToken.current, managerName: managerName))
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let data = try await send(req)
        return try decoder.decode(Response.self, from: data).token
    }

    func revokeLink(token: String) async throws {
        let req = try await request(
            path: "/links/\(token.lowercased())/revoke", method: "POST"
        )
        _ = try await send(req)
    }

    /// Self-heal path for when the local record of a token is gone (e.g. an
    /// app reinstall wipes the on-device roster, but the Keychain-backed
    /// `ManagerToken` survives) — mint then 409s with no local token to
    /// revoke via `revokeLink`. Scoped server-side to this device's own
    /// `managerToken`, so it can only revoke a link minted by this manager,
    /// never an arbitrary player's link.
    func revokeLinkByName(playerName: String) async throws {
        struct Body: Encodable { let playerName: String; let managerToken: String }
        var req = try await request(path: "/links/revoke-by-name", method: "POST")
        req.httpBody = try encoder.encode(Body(playerName: playerName, managerToken: ManagerToken.current))
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        _ = try await send(req)
    }

    // swiftlint:disable:next function_parameter_count
    func pushRound(
        gameToken: UUID,
        mode: String,
        roundNumber: Int,
        deadline: Date?,
        gameName: String?,
        fixtures: [FixturePushItem],
        jokerEnabled: Bool,
        managerSuffix: String?,
        managerName: String?,
        players: [PlayerPushItem],
        extraJSON: String? = nil,
        previousResultsRoundNumber: Int? = nil,
        previousResultsJSON: String? = nil
    ) async throws {
        struct Body: Encodable {
            let mode: String
            let roundNumber: Int
            let deadline: String?
            let gameName: String?
            let fixtures: [FixturePushItem]
            let jokerEnabled: Bool
            let managerSuffix: String?
            let managerName: String?
            let managerToken: String
            let players: [PlayerPushItem]
            /// Opaque, mode-specific round data (e.g. Killer's phase/roster) —
            /// pre-serialized by the caller so this client stays mode-agnostic.
            let extra: String?
            /// The most-recently-closed round's outcome — same opaque-JSON-
            /// string convention as `extra`, paired with the round it's for.
            let previousResultsRoundNumber: Int?
            let previousResults: String?
        }
        let deadlineStr = deadline.map { ISO8601DateFormatter().string(from: $0) }
        var req = try await request(
            path: "/games/\(gameToken.uuidString.lowercased())/push", method: "POST"
        )
        req.httpBody = try encoder.encode(
            Body(mode: mode, roundNumber: roundNumber, deadline: deadlineStr, gameName: gameName,
                 fixtures: fixtures, jokerEnabled: jokerEnabled,
                 managerSuffix: managerSuffix, managerName: managerName,
                 managerToken: ManagerToken.current, players: players, extra: extraJSON,
                 previousResultsRoundNumber: previousResultsRoundNumber, previousResults: previousResultsJSON)
        )
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        _ = try await send(req)
    }

    func listSubmissions(gameToken: UUID, round: Int) async throws -> [SubmissionItem] {
        struct Response: Decodable { let submissions: [SubmissionItem] }
        let req = try await request(
            path: "/games/\(gameToken.uuidString.lowercased())/submissions?round=\(round)", method: "GET"
        )
        let data = try await send(req)
        return try decoder.decode(Response.self, from: data).submissions
    }

    func approve(submissionId: String, gameToken: UUID) async throws -> ApproveResult {
        let path = "/games/\(gameToken.uuidString.lowercased())/submissions/\(submissionId.lowercased())/approve"
        let req = try await request(path: path, method: "POST")
        let data = try await send(req)
        return try decoder.decode(ApproveResult.self, from: data)
    }

    func reject(submissionId: String, gameToken: UUID) async throws {
        let path = "/games/\(gameToken.uuidString.lowercased())/submissions/\(submissionId.lowercased())/reject"
        let req = try await request(path: path, method: "POST")
        _ = try await send(req)
    }

    /// Removes this game's round/enrollment/submission rows from the cloud.
    /// Call when the game is deleted on-device so cloud data doesn't linger.
    func deleteGame(gameToken: UUID) async throws {
        let req = try await request(
            path: "/games/\(gameToken.uuidString.lowercased())", method: "DELETE"
        )
        _ = try await send(req)
    }

    // ── Internals ─────────────────────────────────────────────────────────────

    private func request(path: String, method: String) async throws -> URLRequest {
        let base = await AppAttestService.shared.authorityURL()
        guard let url = URL(string: path, relativeTo: base) else { throw APIError.badURL }
        var req = URLRequest(url: url)
        req.httpMethod = method
        for (field, value) in await AppAttestService.shared.authorizationHeaders() {
            req.setValue(value, forHTTPHeaderField: field)
        }
        return req
    }

    @discardableResult
    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.badStatus(-1, body: String(data: data, encoding: .utf8))
        }
        guard (200..<300).contains(http.statusCode) else {
            try await MaintenanceCheck.check(status: http.statusCode, data: data)
            throw APIError.badStatus(http.statusCode, body: String(data: data, encoding: .utf8))
        }
        await MaintenanceState.shared.clear()
        return data
    }
}
