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

    /// Always reads worker-api-v2 — the only backend RedesignV2's submission
    /// flow (Sync's pushes, this badge, the inbox) writes to. Every V2 call
    /// site used to pass its own `baseURLOverride` (or omit it and silently
    /// fall back to V1's separate aggregate, which Sync never pushes to —
    /// the bell would read 0 pending and hide itself even when players had
    /// real submissions waiting in v2). Fixed by making this store single-
    /// sourced instead of override-dependent.
    func refresh() async {
        do {
            pendingCount = try await SubmissionsClient.shared.listPendingSubmissions(baseURLOverride: SubmissionsClient.v2BaseURL).count
        } catch {
            badgeLog.warning("Badge refresh failed: \(error.localizedDescription)")
        }
    }
}
