import Combine
import Foundation

/// Shape both Cloudflare Workers return when the global outage flag is on —
/// see worker/src/outage.ts and worker-api/src/outage.ts. Wire contract only;
/// the flag itself is named "outage" server-side to avoid colliding with the
/// unrelated nightly data-sync "maintenance" cron.
private struct MaintenanceResponse: Decodable {
    let error: String
    let message: String?
}

enum MaintenanceError: LocalizedError {
    case maintenance(message: String)

    var errorDescription: String? {
        switch self {
        case .maintenance(let message): return message
        }
    }
}

/// App-wide "the backend is in maintenance mode" flag, set from any cloud
/// call site (sports data, backup, publish, manager, submissions, attest) so
/// a single banner near the app root can cover every screen, not just the
/// one that happened to notice.
@MainActor
final class MaintenanceState: ObservableObject {
    static let shared = MaintenanceState()

    @Published private(set) var isActive = false
    @Published private(set) var message: String?

    private init() {}

    func activate(message: String) {
        isActive = true
        self.message = message
    }

    /// Called after any cloud request succeeds, so the banner clears once the
    /// outage is lifted rather than sticking around until the next launch.
    func clear() {
        isActive = false
        message = nil
    }
}

enum MaintenanceCheck {
    /// Call right after receiving a non-2xx HTTP response, before mapping the
    /// generic error. If this is the maintenance shape, records it in
    /// `MaintenanceState` and throws a friendlier `MaintenanceError.maintenance`
    /// instead of the caller's usual generic status error.
    static func check(status: Int, data: Data) async throws {
        guard status == 503,
              let info = try? JSONDecoder().decode(MaintenanceResponse.self, from: data),
              info.error == "maintenance"
        else { return }
        let text = info.message ?? "We're doing scheduled maintenance — back shortly."
        await MaintenanceState.shared.activate(message: text)
        throw MaintenanceError.maintenance(message: text)
    }
}
