import CryptoKit
import Foundation
import StoreKit
#if canImport(DeviceCheck)
import DeviceCheck
#endif

/// Apple App Attest client — regional JWT edition.
///
/// On first launch the manager's regional authority is resolved once from the
/// StoreKit storefront + leagues.json storefrontMap, then persisted to
/// UserDefaults forever (the manager's data follows their home authority).
/// A single Secure-Enclave key is attested against that authority. Subsequent
/// requests receive a 15-min ES256 JWT (refreshed when within 60 s of expiry)
/// rather than a per-request assertion — one Apple round-trip mints a token
/// valid for all protected routes on both the authority and sports shards.
actor AppAttestService {
    static let shared = AppAttestService()

    private let defaults = UserDefaults.standard
    private let authorityDefaultsKey = "attestAuthorityURL"
    private let keyIdDefaultsKey     = "appattest.keyId"
    private let jwtRefreshBuffer: TimeInterval = 60

    // MARK: - Authority URL

    private var _authorityURL: URL?

    /// The manager's home authority URL, resolved once and cached forever.
    func authorityURL() async -> URL {
        if let cached = _authorityURL { return cached }
        if let stored = defaults.string(forKey: authorityDefaultsKey),
           let url = URL(string: stored) {
            _authorityURL = url
            return url
        }
        let resolved = await resolveAuthority()
        _authorityURL = resolved
        defaults.set(resolved.absoluteString, forKey: authorityDefaultsKey)
        return resolved
    }

    private func resolveAuthority() async -> URL {
        let countryCode = await Storefront.current?.countryCode
        let regionKey: String
        if let code = countryCode, let key = Leagues.storefrontMap[code] {
            regionKey = key
        } else {
            regionKey = Leagues.defaultAuthority
        }
        let urlString = Leagues.authorities[regionKey]
            ?? "https://api.\(regionKey).sportsmanager.site"
        return URL(string: urlString) ?? URL(string: "https://api.uk.sportsmanager.site")!
    }

    // MARK: - JWT cache + single-flight mint

    private var cachedToken: String?
    private var tokenExpiresAt: Date?
    private var jwtTask: Task<String, Error>?

    /// Returns `["Authorization": "Bearer <token>"]`, or `[:]` if attestation
    /// is unavailable (Simulator, transient error). Never throws.
    func authorizationHeaders() async -> [String: String] {
        #if canImport(DeviceCheck)
        guard DCAppAttestService.shared.isSupported else { return [:] }
        do {
            let token = try await jwt()
            return ["Authorization": "Bearer \(token)"]
        } catch {
            return [:]
        }
        #else
        return [:]
        #endif
    }

    #if canImport(DeviceCheck)
    private var service: DCAppAttestService { .shared }

    private func jwt() async throws -> String {
        if let token = cachedToken, let expiry = tokenExpiresAt,
           Date().addingTimeInterval(jwtRefreshBuffer) < expiry {
            return token
        }
        if let inFlight = jwtTask { return try await inFlight.value }

        let task = Task<String, Error> {
            let authority = await self.authorityURL()
            let keyId     = try await self.attestedKeyId(authority: authority)
            let challenge = try await self.fetchChallenge(baseURL: authority)
            let assertion = try await self.assertion(keyId: keyId, challenge: challenge)
            return try await self.mintJWT(
                authority: authority, keyId: keyId,
                challenge: challenge, assertion: assertion
            )
        }
        jwtTask = task
        defer { jwtTask = nil }
        return try await task.value
    }

    // MARK: - JWT mint via POST /attest/assert

    private struct AssertResponse: Decodable { let token: String; let expiresAt: String }

    private func mintJWT(
        authority: URL, keyId: String,
        challenge: String, assertion: String
    ) async throws -> String {
        let url = attestRoot(for: authority).appendingPathComponent("attest/assert")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(keyId, forHTTPHeaderField: "X-Attest-Key-Id")
        req.setValue(challenge, forHTTPHeaderField: "X-Attest-Challenge")
        req.setValue(assertion, forHTTPHeaderField: "X-Attest-Assertion")
        let (data, response) = try await URLSession.shared.data(for: req)
        try Self.check(response, data: data)
        let parsed = try JSONDecoder().decode(AssertResponse.self, from: data)
        cachedToken    = parsed.token
        tokenExpiresAt = ISO8601DateFormatter().date(from: parsed.expiresAt)
        return parsed.token
    }

    // MARK: - Key enrolment (once per authority)

    private var attestationTask: Task<String, Error>?

    private func attestedKeyId(authority: URL) async throws -> String {
        if let existing = storedKeyId() { return existing }
        if let inFlight = attestationTask { return try await inFlight.value }

        let task = Task<String, Error> {
            let keyId          = try await self.service.generateKey()
            let challengeValue = try await self.fetchChallenge(baseURL: authority)
            let attestation    = try await self.service.attestKey(
                keyId, clientDataHash: self.clientDataHash(challengeValue)
            )
            try await self.register(
                baseURL: authority, keyId: keyId,
                attestation: attestation.base64EncodedString(),
                challenge: challengeValue
            )
            self.storeKeyId(keyId)
            return keyId
        }
        attestationTask = task
        defer { attestationTask = nil }
        return try await task.value
    }

    // MARK: - Assertion

    private func assertion(keyId: String, challenge: String) async throws -> String {
        let data = try await service.generateAssertion(
            keyId, clientDataHash: clientDataHash(challenge)
        )
        return data.base64EncodedString()
    }

    private func clientDataHash(_ challenge: String) -> Data {
        Data(SHA256.hash(data: Data(challenge.utf8)))
    }
    #endif

    // MARK: - Enrolment endpoints (unattested)

    private struct ChallengeResponse: Decodable { let challenge: String }

    private func attestRoot(for baseURL: URL) -> URL {
        var c = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) ?? URLComponents()
        c.path = ""; c.query = nil; c.fragment = nil
        return c.url ?? baseURL
    }

    private func fetchChallenge(baseURL: URL) async throws -> String {
        let url = attestRoot(for: baseURL).appendingPathComponent("attest/challenge")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        let (data, response) = try await URLSession.shared.data(for: req)
        try Self.check(response, data: data)
        return try JSONDecoder().decode(ChallengeResponse.self, from: data).challenge
    }

    private func register(
        baseURL: URL, keyId: String, attestation: String, challenge: String
    ) async throws {
        let url = attestRoot(for: baseURL).appendingPathComponent("attest/register")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode([
            "keyId": keyId, "attestation": attestation, "challenge": challenge,
        ])
        let (data, response) = try await URLSession.shared.data(for: req)
        try Self.check(response, data: data)
    }

    private static func check(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError.badStatus(
                (response as? HTTPURLResponse)?.statusCode ?? -1,
                body: String(data: data, encoding: .utf8)
            )
        }
    }

    // MARK: - Key persistence (single key, not per-host)

    private func storedKeyId() -> String? { defaults.string(forKey: keyIdDefaultsKey) }
    private func storeKeyId(_ keyId: String) { defaults.set(keyId, forKey: keyIdDefaultsKey) }
}
