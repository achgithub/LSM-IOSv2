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

    /// `baseURLOverride`: nil (every existing call site) keeps reading V1's
    /// aggregate pending count exactly as before. `SyncCoordinator` passes
    /// worker-api-v2's URL after its own pushes, so the post-sync count
    /// reflects what Sync itself just pushed there — not V1's count.
    func refresh(baseURLOverride: URL? = nil) async {
        do {
            pendingCount = try await SubmissionsClient.shared.listPendingSubmissions(baseURLOverride: baseURLOverride).count
        } catch {
            badgeLog.warning("Badge refresh failed: \(error.localizedDescription)")
        }
    }
}
