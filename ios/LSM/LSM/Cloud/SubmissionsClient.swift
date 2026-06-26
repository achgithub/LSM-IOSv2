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
}

struct PlayerPushItem: Encodable {
    let token: String
    let localPlayerId: String
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
    // Predictor
    let scores: [PredictorScore]?
}

struct PredictorScore: Decodable {
    let fixtureId: Int
    let home: Int
    let away: Int
    let isJoker: Bool?
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

    private static let canonicalBase = URL(string: "https://lsm-uk-worker.sportsmanager.workers.dev")!
    private let base = SubmissionsClient.canonicalBase

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

    func mintLink(playerName: String) async throws -> String {
        struct Body: Encodable { let playerName: String; let managerToken: String }
        struct Response: Decodable { let token: String }
        var req = try await request(path: "/links", method: "POST")
        req.httpBody = try encoder.encode(Body(playerName: playerName, managerToken: ManagerToken.current))
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

    func pushRound(
        gameToken: UUID,
        mode: String,
        roundNumber: Int,
        deadline: Date?,
        fixtures: [FixturePushItem],
        jokerEnabled: Bool,
        managerSuffix: String?,
        players: [PlayerPushItem]
    ) async throws {
        struct Body: Encodable {
            let mode: String
            let roundNumber: Int
            let deadline: String?
            let fixtures: [FixturePushItem]
            let jokerEnabled: Bool
            let managerSuffix: String?
            let managerToken: String
            let players: [PlayerPushItem]
        }
        let deadlineStr = deadline.map { ISO8601DateFormatter().string(from: $0) }
        var req = try await request(
            path: "/games/\(gameToken.uuidString.lowercased())/push", method: "POST"
        )
        req.httpBody = try encoder.encode(
            Body(mode: mode, roundNumber: roundNumber, deadline: deadlineStr,
                 fixtures: fixtures, jokerEnabled: jokerEnabled,
                 managerSuffix: managerSuffix, managerToken: ManagerToken.current,
                 players: players)
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

    // ── Internals ─────────────────────────────────────────────────────────────

    private func request(path: String, method: String) async throws -> URLRequest {
        guard let url = URL(string: path, relativeTo: base) else { throw APIError.badURL }
        var req = URLRequest(url: url)
        req.httpMethod = method
        for (field, value) in await AppAttestService.shared.authorizationHeaders(for: base) {
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
            throw APIError.badStatus(http.statusCode, body: String(data: data, encoding: .utf8))
        }
        return data
    }
}
