import Foundation

enum APIError: LocalizedError {
    case badURL
    case badStatus(Int, body: String?)

    /// User-facing copy only — never the raw status/body (that's logged to
    /// `DiagnosticLog` at the throw site instead, for a Report a Bug
    /// attachment, not shown on screen). Every display site across the app
    /// reads this one property, so bucketing it here is a single fix for
    /// all of them rather than touching each site individually.
    var errorDescription: String? {
        let hint = AppString("Try again, and if this keeps happening, send a report from Settings → Report a Bug.")
        switch self {
        case .badURL:
            return AppString("Something went wrong. \(hint)")
        case .badStatus(let code, _):
            let reason: String
            switch code {
            case 401, 403: reason = AppString("Couldn't verify this device with the server (\(code)).")
            case 404: reason = AppString("Couldn't find that (\(code)).")
            case 429: reason = AppString("Too many requests — please wait a moment (\(code)).")
            case 500...599: reason = AppString("The server had a problem (\(code)).")
            default: reason = AppString("Something went wrong reaching the server (\(code)).")
            }
            return "\(reason) \(hint)"
        }
    }
}

/// Client for a per-league Worker (read-only sports-data API). Each league
/// builds its own client via `LeagueOption.client` / `init(baseURL:)`.
actor APIClient {
    private let base: URL
    private let decoder = JSONDecoder()

    init(baseURL: URL) { self.base = baseURL }

    func teams() async throws -> [TeamDTO] { try await get("/teams") }
    func standings() async throws -> [StandingDTO] { try await get("/standings") }
    // One shared cache server-side — no freshness tier. Free vs subscriber is an
    // app-side rewarded-ad gate on the refresh action (see AdGate), not the data.
    func scores() async throws -> [ScoreDTO] { try await get("/scores") }

    func fixtures(dateFrom: String? = nil, dateTo: String? = nil, matchday: Int? = nil) async throws -> [MatchDTO] {
        var query: [URLQueryItem] = []
        if let dateFrom { query.append(URLQueryItem(name: "dateFrom", value: dateFrom)) }
        if let dateTo { query.append(URLQueryItem(name: "dateTo", value: dateTo)) }
        if let matchday { query.append(URLQueryItem(name: "matchday", value: String(matchday))) }
        return try await get("/fixtures", query: query)
    }

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        guard var components = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw APIError.badURL
        }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw APIError.badURL }
        var request = URLRequest(url: url)
        // App Attest: prove this is the genuine app so the Worker serves the
        // licensed feed. Best-effort — no headers on Simulator / pre-enrolment,
        // and the Worker decides whether to accept (see AppAttestService).
        for (field, value) in await AppAttestService.shared.authorizationHeaders() {
            request.setValue(value, forHTTPHeaderField: field)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            let body = String(data: data, encoding: .utf8)
            await DiagnosticLog.shared.log("non-HTTP response for \(url.absoluteString): \(body ?? "")", category: "network")
            throw APIError.badStatus(-1, body: body)
        }
        guard (200..<300).contains(http.statusCode) else {
            try await MaintenanceCheck.check(status: http.statusCode, data: data)
            let body = String(data: data, encoding: .utf8)
            await DiagnosticLog.shared.log("\(http.statusCode) for \(url.absoluteString): \(body ?? "")", category: "network")
            throw APIError.badStatus(http.statusCode, body: body)
        }
        await MaintenanceState.shared.clear()
        return try decoder.decode(T.self, from: data)
    }
}
