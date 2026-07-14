import CryptoKit
import Foundation
import Security
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

        let task = Task<String, Error> { try await self.attemptJWT(freshAttest: false) }
        jwtTask = task
        defer { jwtTask = nil }
        return try await task.value
    }

    private func attemptJWT(freshAttest: Bool) async throws -> String {
        let authority = await authorityURL()
        let keyId     = try await attestedKeyId(authority: authority, fresh: freshAttest)
        let challenge = try await fetchChallenge(baseURL: authority)
        let assertion = try await assertion(keyId: keyId, challenge: challenge)
        do {
            return try await mintJWT(authority: authority, keyId: keyId,
                                     challenge: challenge, assertion: assertion)
        } catch APIError.badStatus(403, _) where !freshAttest {
            // Stored key's public key in the authority DB doesn't verify — stale
            // registration (e.g. re-install, or DB was seeded from a dev session).
            // Clear the key so attestedKeyId generates and registers a fresh one.
            deleteKeyId()
            return try await attemptJWT(freshAttest: true)
        }
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
        try await Self.check(response, data: data)
        let parsed = try JSONDecoder().decode(AssertResponse.self, from: data)
        cachedToken    = parsed.token
        tokenExpiresAt = Self.parseExpiry(parsed.expiresAt)
        return parsed.token
    }

    /// Parses the authority's `expiresAt`, which is emitted via JS
    /// `Date.toISOString()` and so carries fractional seconds (`…T12:00:00.000Z`).
    /// A bare `ISO8601DateFormatter` only understands `.withInternetDateTime` and
    /// silently returns nil on the `.000` — which left `tokenExpiresAt` nil and
    /// re-ran the full attest mint on every cloud call. Try fractional first, then
    /// fall back to the plain form so we're robust if the server format ever drifts.
    static func parseExpiry(_ string: String) -> Date? {
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFractional.date(from: string) { return date }
        return ISO8601DateFormatter().date(from: string)
    }

    // MARK: - Key enrolment (once per authority)

    private var attestationTask: Task<String, Error>?

    private func attestedKeyId(authority: URL, fresh: Bool = false) async throws -> String {
        if !fresh, let existing = storedKeyId() { return existing }
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
        try await Self.check(response, data: data)
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
            "managerToken": ManagerToken.current,
        ])
        let (data, response) = try await URLSession.shared.data(for: req)
        try await Self.check(response, data: data)
    }

    private static func check(_ response: URLResponse, data: Data) async throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            try await MaintenanceCheck.check(status: status, data: data)
            throw APIError.badStatus(status, body: String(data: data, encoding: .utf8))
        }
        await MaintenanceState.shared.clear()
    }

    // MARK: - Key persistence (single key, not per-host)
    //
    // Keychain-backed, not UserDefaults — matches ManagerToken's rationale
    // (UserDefaults is plaintext-readable via backup tools / device access).
    // The keyId itself grants nothing without the Secure-Enclave-protected
    // private key to sign assertions, but Keychain storage is the low-cost
    // consistent choice. Migrates any value left in UserDefaults from
    // earlier builds, then deletes it there.

    private static let keychainService = "com.sportsmanager.LMS"
    private static let keychainAccount = "appattestKeyId"

    private func storedKeyId() -> String? {
        if let value = Self.keychainValue() { return value }
        if let legacy = defaults.string(forKey: keyIdDefaultsKey) {
            Self.saveKeyId(legacy)
            defaults.removeObject(forKey: keyIdDefaultsKey)
            return legacy
        }
        return nil
    }

    private func storeKeyId(_ keyId: String) { Self.saveKeyId(keyId) }

    private func deleteKeyId() {
        defaults.removeObject(forKey: keyIdDefaultsKey)
        Self.deleteKeyIdFromKeychain()
    }

    private static func keychainValue() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else { return nil }
        return value
    }

    private static func saveKeyId(_ value: String) {
        guard let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data,
        ]
        SecItemDelete(query as CFDictionary) // remove any prior value
        SecItemAdd(query as CFDictionary, nil)
    }

    private static func deleteKeyIdFromKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
