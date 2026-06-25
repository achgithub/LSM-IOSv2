import Foundation

/// Cloud Backup client (Phase 2) — pushes/pulls a `BackupBundle` blob to/from
/// the Worker's R2-backed `/backup/:id` route. Mirrors `APIClient`'s
/// conventions (URLComponents/URLRequest, `AppAttestService` headers,
/// `APIError`-style errors) but for a single shared write/read route rather
/// than a per-league read-only one.
///
/// Always talks to one CANONICAL shard, never `Leagues.home` — backup's R2
/// blob genuinely is region-agnostic (no D1 involved), but Publish's
/// `publish_links` lookup lives in ONE shard's D1 (`uk`'s). If this pointed
/// at whichever shard happens to be the user's home league, a manager whose
/// home league is on the `eu` shard would publish a link the Pages Function
/// (wired to a fixed `WORKER_BASE_URL`) could never find — a permanent 404,
/// not a "either shard works" situation. Same hardcoded-canonical-shard
/// rationale as `Leagues.registryURL`; keep both pointed at the same shard.
actor SnapshotClient {
    static let shared = SnapshotClient()

    private static let canonicalBase = URL(string: "https://lsm-uk-worker.sportsmanager.workers.dev")!
    private let base = SnapshotClient.canonicalBase
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

    /// Publish (or republish, passing the same `existingLinkId`/`ownerToken`)
    /// a Predictor predictions-league snapshot, PIN-gated server-side for
    /// viewers. Returns the link id for `/l/<id>` (stable across republishes)
    /// and the owner token to store on `Game` and pass back next time.
    ///
    /// `ownerToken` — NOT the PIN — is the republish credential while
    /// attestation is off (see worker/src/routes/publish.ts): the PIN is
    /// short and viewer-facing, brute-forceable in seconds, and was
    /// deliberately removed from this role after a security review flagged
    /// it as a takeover vector. `pin` is the PIN to set going forward.
    func publish(
        _ snapshot: PublishSnapshot, pin: String, existingLinkId: UUID?, ownerToken: String?
    ) async throws -> (id: UUID, ownerToken: String) {
        struct Body: Encodable {
            let id: String?
            let ownerToken: String?
            let pin: String
            let snapshot: PublishSnapshot
        }
        struct Response: Decodable { let id: String; let ownerToken: String }

        // No trailing slash — Hono's sub-router mounted at "/publish" matches
        // the bare path "/publish", not "/publish/" (confirmed live: the
        // trailing-slash form 404s). Verified against production 2026-06-25.
        var request = try await request(path: "/publish", method: "POST")
        request.httpBody = try encoder.encode(
            Body(id: existingLinkId?.uuidString, ownerToken: ownerToken, pin: pin, snapshot: snapshot)
        )
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let data = try await send(request)
        let response = try decoder.decode(Response.self, from: data)
        guard let id = UUID(uuidString: response.id) else {
            throw APIError.badStatus(-1, body: "Worker returned an invalid link id")
        }
        return (id, response.ownerToken)
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
