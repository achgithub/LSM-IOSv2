import Foundation

/// Lifecycle state returned by GET /manager/status.
struct ManagerLifecycleStatus: Decodable {
    /// "active" | "warned" | "pending_delete" | "not_found"
    let state: String
    let warnedAt: String?
    let scheduledDeleteAt: String?
    let daysUntilDeletion: Int?

    var isActive: Bool { state == "active" }
    var isWarned: Bool { state == "warned" }
    var isPendingDelete: Bool { state == "pending_delete" }

    var bannerMessage: String? {
        switch state {
        case "warned":
            return "No activity for 45 days — your cloud data will be deleted in 15 days if no round is opened."
        case "pending_delete":
            if let days = daysUntilDeletion {
                return days > 0
                    ? "Subscription ended — cloud data will be deleted in \(days) day\(days == 1 ? "" : "s")."
                    : "Cloud data is scheduled for deletion."
            }
            return "Cloud data is scheduled for deletion."
        default:
            return nil
        }
    }
}

/// Client for manager lifecycle endpoints (/manager/*) on the authority worker.
actor ManagerLifecycleClient {
    static let shared = ManagerLifecycleClient()

    private let decoder = JSONDecoder()

    private init() {
        decoder.keyDecodingStrategy = .convertFromSnakeCase
    }

    func status() async -> ManagerLifecycleStatus? {
        guard let req = await makeRequest(path: "/manager/status", method: "GET") else { return nil }
        var r = req
        r.setValue(ManagerToken.current, forHTTPHeaderField: "X-Manager-Token")
        do {
            let (data, response) = try await URLSession.shared.data(for: r)
            try await checkMaintenance(response, data: data)
            return try decoder.decode(ManagerLifecycleStatus.self, from: data)
        } catch {
            return nil
        }
    }

    func unsubscribe() async {
        guard var req = await makeRequest(path: "/manager/unsubscribe", method: "POST") else { return }
        req.setValue(ManagerToken.current, forHTTPHeaderField: "X-Manager-Token")
        guard let (data, response) = try? await URLSession.shared.data(for: req) else { return }
        try? await checkMaintenance(response, data: data)
    }

    func resubscribe() async {
        guard var req = await makeRequest(path: "/manager/resubscribe", method: "POST") else { return }
        req.setValue(ManagerToken.current, forHTTPHeaderField: "X-Manager-Token")
        guard let (data, response) = try? await URLSession.shared.data(for: req) else { return }
        try? await checkMaintenance(response, data: data)
    }

    /// This client never surfaces generic errors to its callers (they treat a
    /// failure as "no lifecycle info available" and move on), but a
    /// maintenance response is worth surfacing globally — see MaintenanceState.
    private func checkMaintenance(_ response: URLResponse, data: Data) async throws {
        guard let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) else {
            await MaintenanceState.shared.clear()
            return
        }
        try await MaintenanceCheck.check(status: http.statusCode, data: data)
    }

    private func makeRequest(path: String, method: String) async -> URLRequest? {
        let base = await AppAttestService.shared.authorityURL()
        guard let url = URL(string: path, relativeTo: base) else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = method
        for (field, value) in await AppAttestService.shared.authorizationHeaders() {
            req.setValue(value, forHTTPHeaderField: field)
        }
        return req
    }
}
