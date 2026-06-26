import Foundation

/// Lifecycle state returned by GET /manager/:token/status.
struct ManagerLifecycleStatus: Decodable {
    /// "active" | "warned" | "pending_delete" | "not_found"
    let state: String
    let warnedAt: String?
    let scheduledDeleteAt: String?
    let daysUntilDeletion: Int?

    var isActive: Bool { state == "active" }
    var isWarned: Bool { state == "warned" }
    var isPendingDelete: Bool { state == "pending_delete" }

    /// Human-readable summary for the Cloud Settings footer.
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

/// Client for Phase 6 manager lifecycle endpoints.
actor ManagerLifecycleClient {
    static let shared = ManagerLifecycleClient()

    private static let base = URL(string: "https://lsm-uk-worker.sportsmanager.workers.dev")!
    private let decoder = JSONDecoder()

    private init() {
        decoder.keyDecodingStrategy = .convertFromSnakeCase
    }

    /// Fetch lifecycle status — call when Cloud Settings is opened.
    func status() async -> ManagerLifecycleStatus? {
        guard let url = URL(string: "/manager/status", relativeTo: Self.base) else { return nil }
        var req = await request(url: url, method: "GET")
        req.setValue(ManagerToken.current, forHTTPHeaderField: "X-Manager-Token")
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            return try decoder.decode(ManagerLifecycleStatus.self, from: data)
        } catch {
            return nil
        }
    }

    /// Signal that the cloud bundle subscription has lapsed.
    /// Idempotent — safe to call every time Settings opens while unsubscribed.
    func unsubscribe() async {
        guard let url = URL(string: "/manager/unsubscribe", relativeTo: Self.base) else { return }
        var req = await request(url: url, method: "POST")
        req.setValue(ManagerToken.current, forHTTPHeaderField: "X-Manager-Token")
        _ = try? await URLSession.shared.data(for: req)
    }

    /// Clear the pending deletion if the manager re-subscribes.
    func resubscribe() async {
        guard let url = URL(string: "/manager/resubscribe", relativeTo: Self.base) else { return }
        var req = await request(url: url, method: "POST")
        req.setValue(ManagerToken.current, forHTTPHeaderField: "X-Manager-Token")
        _ = try? await URLSession.shared.data(for: req)
    }

    private func request(url: URL, method: String) async -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = method
        for (field, value) in await AppAttestService.shared.authorizationHeaders(for: Self.base) {
            req.setValue(value, forHTTPHeaderField: field)
        }
        return req
    }
}
