import Foundation

/// Cloud Backup client (Phase 2) — pushes/pulls a `BackupBundle` blob to/from
/// the Worker's R2-backed `/backup/:id` route. Mirrors `APIClient`'s
/// conventions (URLComponents/URLRequest, `AppAttestService` headers,
/// `APIError`-style errors) but for a single shared write/read route rather
/// than a per-league read-only one.
///
/// Backup/restore is region-agnostic (the blob is self-contained, not scoped
/// to a league), so this always talks to the home league's shard — either
/// shard would do, same rationale as `Leagues.registryURL`.
actor SnapshotClient {
    static let shared = SnapshotClient()

    private let base = Leagues.home.workerURL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    /// Push a backup blob, keyed by the manager's restore-code `id`. Overwrites
    /// whatever was previously stored at that id.
    func backup(_ bundle: BackupBundle, id: UUID) async throws {
        let body = try encoder.encode(bundle)
        var request = try await request(path: "/backup/\(id.uuidString)", method: "PUT")
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        _ = try await send(request)
    }

    /// Pull the bundle stored under a restore-code `id`.
    func restore(id: UUID) async throws -> BackupBundle {
        let request = try await request(path: "/backup/\(id.uuidString)", method: "GET")
        let data = try await send(request)
        return try decoder.decode(BackupBundle.self, from: data)
    }

    private func request(path: String, method: String) async throws -> URLRequest {
        guard let url = URL(string: path, relativeTo: base) else { throw APIError.badURL }
        var request = URLRequest(url: url)
        request.httpMethod = method
        for (field, value) in await AppAttestService.shared.authorizationHeaders(for: base) {
            request.setValue(value, forHTTPHeaderField: field)
        }
        return request
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
