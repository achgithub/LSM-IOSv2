import Foundation

/// Errors specific to the email/OTP account routes — surfaced with copy
/// tailored to what actually went wrong (wrong code vs expired vs rate
/// limited), rather than APIError's generic per-status-code copy.
enum AccountError: LocalizedError {
    case incorrectCode
    case codeExpired
    case tooManyAttempts
    case cooldown(retryAfterSeconds: Int)
    case emailMismatch
    /// Server-side counterpart of `Entitlements.canUseCloud` — the app hides
    /// the registration form below leagues_3, so this only surfaces if the
    /// tier lapsed mid-flow or the client's view of it is stale.
    case cloudTierRequired
    case other(APIError)

    var errorDescription: String? {
        switch self {
        case .incorrectCode:
            return AppString("That code wasn't right. Check your email and try again.")
        case .codeExpired:
            return AppString("That code has expired or was already used. Request a new one.")
        case .tooManyAttempts:
            return AppString("Too many incorrect attempts. Request a new code.")
        case .cooldown(let seconds):
            return AppString("Please wait \(seconds)s before requesting another code.")
        case .emailMismatch:
            return AppString("That code was issued for a different email address.")
        case .cloudTierRequired:
            return AppString("Registering an email for recovery is part of the 3 Leagues plan and above.")
        case .other(let apiError):
            return apiError.errorDescription
        }
    }
}

/// Client for /account/* on the authority worker — email registration for
/// device recovery. Not a login/session system: register links an email to
/// this device's manager_token once; link-device (used by a different,
/// new/lost-phone device) recovers that manager_token via OTP. See
/// worker-api's routes/account.ts header comment for the full picture.
actor AccountClient {
    static let shared = AccountClient()

    private let encoder = JSONEncoder()

    // MARK: - Register (already-live device)

    func registerRequest(email: String) async throws {
        struct Body: Encodable { let email: String }
        var req = try await request(path: "/account/register", method: "POST", includeManagerToken: true)
        req.httpBody = try encoder.encode(Body(email: email))
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        _ = try await send(req)
    }

    /// `keyId` is this device's own App Attest key — the server records it
    /// as the account's `active_key_id`, the same identity a later
    /// link-device transfer will need to match or supersede.
    func registerVerify(email: String, otp: String) async throws {
        let keyId = try await AppAttestService.shared.currentKeyId()
        struct Body: Encodable { let email: String; let otp: String; let keyId: String }
        var req = try await request(path: "/account/verify", method: "POST", includeManagerToken: true)
        req.httpBody = try encoder.encode(Body(email: email, otp: otp, keyId: keyId))
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        _ = try await send(req)
    }

    // MARK: - Link device (new/lost phone, no attested identity yet)
    //
    // Deliberately never sends X-Manager-Token — a fresh install has no
    // token to send yet, and accessing `ManagerToken.current` here would
    // lazily mint and persist a throwaway UUID before the recovered one is
    // adopted (see ManagerToken.adopt).

    func linkDeviceRequest(email: String) async throws {
        struct Body: Encodable { let email: String }
        var req = try await request(path: "/account/link-device/request", method: "POST")
        req.httpBody = try encoder.encode(Body(email: email))
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        _ = try await send(req)
    }

    /// Returns the recovered manager_token. Nothing about any game is
    /// touched here — see GameSyncClient for pulling games once this token
    /// has been adopted and the device has completed its normal App Attest
    /// register flow.
    func linkDeviceVerify(email: String, otp: String) async throws -> String {
        struct Body: Encodable { let email: String; let otp: String }
        struct Response: Decodable { let managerToken: String }
        var req = try await request(path: "/account/link-device/verify", method: "POST")
        req.httpBody = try encoder.encode(Body(email: email, otp: otp))
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let data = try await send(req)
        return try JSONDecoder().decode(Response.self, from: data).managerToken
    }

    // MARK: - Internals

    private func request(path: String, method: String, includeManagerToken: Bool = false) async throws -> URLRequest {
        let base = await AppAttestService.shared.authorityURL()
        guard let url = URL(string: path, relativeTo: base) else { throw APIError.badURL }
        var req = URLRequest(url: url)
        req.httpMethod = method
        for (field, value) in await AppAttestService.shared.authorizationHeaders() {
            req.setValue(value, forHTTPHeaderField: field)
        }
        if includeManagerToken {
            req.setValue(ManagerToken.current, forHTTPHeaderField: "X-Manager-Token")
        }
        return req
    }

    private struct ServerError: Decodable { let error: String; let retryAfterSeconds: Int? }

    @discardableResult
    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            let body = String(data: data, encoding: .utf8)
            await DiagnosticLog.shared.log("non-HTTP response for \(request.url?.absoluteString ?? ""): \(body ?? "")", category: "account")
            throw APIError.badStatus(-1, body: body)
        }
        guard (200..<300).contains(http.statusCode) else {
            try await MaintenanceCheck.check(status: http.statusCode, data: data)
            let body = String(data: data, encoding: .utf8)
            await DiagnosticLog.shared.log("\(http.statusCode) for \(request.url?.absoluteString ?? ""): \(body ?? "")", category: "account")
            if let server = try? JSONDecoder().decode(ServerError.self, from: data) {
                switch server.error {
                case "incorrect": throw AccountError.incorrectCode
                case "not_found": throw AccountError.codeExpired
                case "too_many_attempts": throw AccountError.tooManyAttempts
                case "email mismatch": throw AccountError.emailMismatch
                case "cloud_tier_required": throw AccountError.cloudTierRequired
                default:
                    if http.statusCode == 429, let retry = server.retryAfterSeconds {
                        throw AccountError.cooldown(retryAfterSeconds: retry)
                    }
                }
            }
            throw AccountError.other(APIError.badStatus(http.statusCode, body: body))
        }
        await MaintenanceState.shared.clear()
        return data
    }
}
