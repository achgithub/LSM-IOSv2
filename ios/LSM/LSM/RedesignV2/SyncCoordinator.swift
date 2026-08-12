import Foundation
import Observation
import OSLog
import SwiftData

private let syncLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "lsm", category: "submissions")

/// One game's push failure, surfaced in the post-sync summary rather than
/// aborting the rest of the sync.
struct SyncGameError: Identifiable {
    let id = UUID()
    let gameName: String
    let message: String
}

/// Outcome of the most recent `SyncCoordinator.sync()` call — mirrors
/// Clubroom2's `SyncResult` shape (push count + pull count + per-item
/// failures), adapted to this app's games/submissions.
struct SyncResult {
    let gamesPushed: Int
    let pendingCount: Int
    let errors: [SyncGameError]
    /// Games with no open round, so nothing was pushed for them — surfaced
    /// separately from `errors` since it isn't a failure, but a manager
    /// still needs to know: until a round opens and a sync pushes it,
    /// that game's player link isn't live yet.
    let skippedNoOpenRound: [String]
}

/// Unified "Sync" action, **RedesignV2 only**: one tap pushes every open
/// round (across LMS/Predictor/Killer) to the Player App and refreshes the
/// pending-submission count, replacing what today is three separate manual
/// flows (per-game "Resend to Player App", pull-to-refresh inside the
/// submission queue, and — unaffected here — approve/reject). V1 keeps its
/// existing per-game flows exactly as they are (`SubmissionQueueView`, each
/// mode's `resend()`); this is not retrofitted there.
///
/// Singleton, injected once at the app root alongside `SubmissionBadgeStore`
/// (see `RootTabView`), same `@Observable @MainActor` shape so every V2
/// screen reads the same live sync state.
///
/// Explicitly does **not** auto-approve anything — approve/reject stays a
/// manual per-submission decision in `SubmissionInboxViewV2`. Sync only
/// pushes open rounds and refreshes visibility of what's pending.
@Observable @MainActor
final class SyncCoordinator {
    static let shared = SyncCoordinator()

    private(set) var isSyncing = false
    private(set) var lastSyncedAt: Date?
    private(set) var lastSyncResult: SyncResult?

    /// worker-api-v2 — the standalone KV-backed Worker being validated in
    /// isolation (see wobbly-greeting-kazoo.md). Deliberately hardcoded here
    /// rather than threaded through settings: this override is scoped to
    /// exactly one call site (this coordinator) for exactly one purpose
    /// (on-device testing of the new backend before any migration decision
    /// is made), not a general per-environment config knob. V1 screens never
    /// see this URL. The Authorization JWT still comes from V1's attestation
    /// authority either way — worker-api-v2 only verifies it.
    private let v2BaseURL = URL(string: "https://api-v2.uk.sportsmanager.site")!

    private init() {}

    /// Pushes every local game (any mode) that currently has an open round,
    /// reusing the *existing* per-game push logic in `PWARoundPusher`
    /// (`pushLMSOrPredictor`/`pushKiller`) — no new push implementation.
    /// Failures are collected per-game rather than aborting the whole sync on
    /// one bad game. Once every push has settled, refreshes
    /// `SubmissionBadgeStore` so the pending count reflects whatever the
    /// pushes just made visible (subject to the backend's own ≤60s KV
    /// propagation window — the summary reads as "as of now", not exact).
    func sync(context: ModelContext) async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        let managerName = UserDefaults.standard.string(forKey: ManagerSettings.nameKey) ?? ""
        let pwaSubmissionsEnabled = UserDefaults.standard.bool(forKey: "pwaSubmissionsEnabled")
        guard Entitlements.shared.canUseCloud, pwaSubmissionsEnabled else {
            // Cloud submissions off (or unavailable at this tier) — nothing to
            // push, but still worth refreshing the badge in case tier/toggle
            // changed since the last look.
            await SubmissionBadgeStore.shared.refresh()
            lastSyncResult = SyncResult(gamesPushed: 0, pendingCount: SubmissionBadgeStore.shared.pendingCount, errors: [], skippedNoOpenRound: [])
            lastSyncedAt = Date()
            return
        }

        let games = (try? context.fetch(FetchDescriptor<Game>())) ?? []
        var pushed = 0
        var errors: [SyncGameError] = []
        var skippedNoOpenRound: [String] = []

        for game in games {
            guard let openRound = game.rounds.first(where: { $0.status == .open }) else {
                skippedNoOpenRound.append(game.name)
                continue
            }
            do {
                switch game.mode {
                case .lms, .predictor:
                    try await PWARoundPusher.pushLMSOrPredictor(
                        game: game, round: openRound, managerName: managerName, context: context,
                        baseURLOverride: v2BaseURL
                    )
                case .killer:
                    try await PWARoundPusher.pushKiller(
                        game: game, round: openRound, managerName: managerName, context: context,
                        baseURLOverride: v2BaseURL
                    )
                }
                pushed += 1
            } catch {
                syncLog.warning("Sync push failed for \(game.name): \(error.localizedDescription)")
                errors.append(SyncGameError(gameName: game.name, message: error.localizedDescription))
            }
        }

        await SubmissionBadgeStore.shared.refresh(baseURLOverride: v2BaseURL)

        lastSyncResult = SyncResult(gamesPushed: pushed, pendingCount: SubmissionBadgeStore.shared.pendingCount, errors: errors, skippedNoOpenRound: skippedNoOpenRound)
        lastSyncedAt = Date()
    }
}
