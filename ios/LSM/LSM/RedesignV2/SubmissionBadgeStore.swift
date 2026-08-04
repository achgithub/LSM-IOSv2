import Foundation
import Observation
import OSLog

private let badgeLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "lsm", category: "submissions")

/// Live count backing the V2 bell badge on Home and Games (`AppHeader`).
/// Singleton, injected once at the app root alongside `Entitlements.shared`
/// (see `RootTabView`), so every V2 screen reads the same cached count
/// instead of each fetching its own copy of the same aggregate endpoint.
@Observable @MainActor
final class SubmissionBadgeStore {
    static let shared = SubmissionBadgeStore()

    private(set) var pendingCount: Int = 0

    private init() {}

    func refresh() async {
        do {
            pendingCount = try await SubmissionsClient.shared.listPendingSubmissions().count
        } catch {
            badgeLog.warning("Badge refresh failed: \(error.localizedDescription)")
        }
    }
}
