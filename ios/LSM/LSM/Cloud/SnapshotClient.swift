import Foundation

/// Cloud Backup + Publish client.
///
/// Backup/restore and publish all live on the regional authority worker
/// (api.{region}.sportsmanager.site). The publish write path is JWT-gated;
/// the viewer unlock path is public and called from the browser, not here.
///
/// The publish share link embeds the region so the Pages Function at
/// /l/:region/:id can route to the correct authority without a global index.
actor SnapshotClient {
    static let shared = SnapshotClient()

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    // MARK: - Backup

    func backup(_ bundle: BackupBundle, id: UUID) async throws {
        let body = try encoder.encode(bundle)
        var request = try await authorityRequest(path: "/backup/\(id.uuidString)", method: "PUT")
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(ManagerToken.current, forHTTPHeaderField: "X-Manager-Token")
        _ = try await send(request)
    }

    func restore(id: UUID) async throws -> BackupBundle {
        let request = try await authorityRequest(path: "/backup/\(id.uuidString)", method: "GET")
        let data = try await send(request)
        return try decoder.decode(BackupBundle.self, from: data)
    }

    // MARK: - Publish

    struct PublishResult {
        let id: UUID
        let ownerToken: String
        let region: String
    }

    /// Publish (or republish) a Predictor snapshot. Returns the link id, owner
    /// token, and region — all three are stored on `Game` so the share link URL
    /// `/l/{region}/{id}` can be reconstructed without a server round-trip.
    func publish(
        _ snapshot: PublishSnapshot, pin: String,
        existingLinkId: UUID?, ownerToken: String?
    ) async throws -> PublishResult {
        struct Body: Encodable {
            let id: String?
            let ownerToken: String?
            let pin: String
            let snapshot: PublishSnapshot
        }
        struct Response: Decodable { let id: String; let ownerToken: String; let region: String }

        var request = try await authorityRequest(path: "/publish", method: "POST")
        request.httpBody = try encoder.encode(
            Body(id: existingLinkId?.uuidString, ownerToken: ownerToken, pin: pin, snapshot: snapshot)
        )
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let data = try await send(request)
        let response = try decoder.decode(Response.self, from: data)
        guard let id = UUID(uuidString: response.id) else {
            throw APIError.badStatus(-1, body: "Worker returned an invalid link id")
        }
        return PublishResult(id: id, ownerToken: response.ownerToken, region: response.region)
    }

    /// Fully removes a published link — the R2 snapshot and the D1 row both
    /// go, so the page 404s immediately rather than staying PIN-gated forever
    /// with no way to pull it down (issue #8). `ownerToken` is the same
    /// republish ownership proof as `publish`.
    func unpublish(id: UUID, ownerToken: String) async throws {
        struct Body: Encodable { let ownerToken: String }

        var request = try await authorityRequest(path: "/publish/\(id.uuidString.lowercased())", method: "DELETE")
        request.httpBody = try encoder.encode(Body(ownerToken: ownerToken))
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        _ = try await send(request)
    }

    // MARK: - Internals

    private func authorityRequest(path: String, method: String) async throws -> URLRequest {
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
