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
    /// Of `gamesPushed`, how many were retried because a *previous* push
    /// never confirmed (`Game.pushPending`), not because the manager picked
    /// them this time — the client-side outbox. Surfaced separately so a
    /// retry-driven push to an unselected game is visible, not silent.
    let retriedOutstanding: Int
}

/// Return shape for `SyncCoordinator.pushGames` — everything `SyncResult`
/// needs except `pendingCount`, which only `sync()`/`retryOutstanding()`
/// know how to fetch (via `SubmissionBadgeStore`) after the push loop ends.
private struct PushGamesOutcome {
    let pushed: Int
    let retried: Int
    let errors: [SyncGameError]
    let skippedNoOpenRound: [String]
}

/// Unified "Sync" action, **RedesignV2 only**: pushes the open round of
/// every game the manager explicitly picks in `SyncGamePickerViewV2`
/// (across LMS/Predictor/Killer) to the Player App and refreshes the
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

    private init() {}

    /// Pushes every **selected** game (any mode) that currently has an open
    /// round, reusing the *existing* per-game push logic in `PWARoundPusher`
    /// (`pushLMSOrPredictor`/`pushKiller`) — no new push implementation.
    /// `gameIDs` is required, not defaulted to "all games": every call site
    /// goes through `SyncGamePickerViewV2` so a manager explicitly picks
    /// which games to push each time, rather than a stray tap fanning out
    /// a network call per game — each push is a billed Worker invocation, so
    /// an unfiltered "sync everything" button was a standing cost risk with
    /// more than a couple of games running (there's deliberately no
    /// select-all shortcut in the picker either, for the same reason).
    /// Failures are collected per-game rather than aborting the whole sync on
    /// one bad game. Once every push has settled, refreshes
    /// `SubmissionBadgeStore` so the pending count reflects whatever the
    /// pushes just made visible (subject to the backend's own ≤60s KV
    /// propagation window — the summary reads as "as of now", not exact).
    func sync(context: ModelContext, gameIDs: Set<UUID>) async {
        guard !isSyncing, !gameIDs.isEmpty else { return }
        isSyncing = true
        defer { isSyncing = false }

        let managerName = UserDefaults.standard.string(forKey: ManagerSettings.nameKey) ?? ""
        let pwaSubmissionsEnabled = UserDefaults.standard.bool(forKey: "pwaSubmissionsEnabled")
        guard Entitlements.shared.canUseCloud, pwaSubmissionsEnabled else {
            // Cloud submissions off (or unavailable at this tier) — nothing to
            // push, but still worth refreshing the badge in case tier/toggle
            // changed since the last look.
            await SubmissionBadgeStore.shared.refresh()
            lastSyncResult = SyncResult(gamesPushed: 0, pendingCount: SubmissionBadgeStore.shared.pendingCount, errors: [], skippedNoOpenRound: [], retriedOutstanding: 0)
            lastSyncedAt = Date()
            return
        }

        let allGames = (try? context.fetch(FetchDescriptor<Game>())) ?? []
        let selected = allGames.filter { gameIDs.contains($0.id) }
        // Writes this device already attempted and never got confirmation
        // for (`Game.pushPending`) — the client-side outbox. Retried
        // alongside the explicit selection even when not picked this time:
        // bounded by what this device already tried, not an open-ended
        // resync, so it doesn't undermine the "manager picks what syncs"
        // design above. Excludes anything already in `selected` to avoid a
        // double push.
        let outstanding = allGames.filter { $0.pushPending && !gameIDs.contains($0.id) }

        let pushedOutstanding = await pushGames(selected + outstanding, managerName: managerName, context: context, outstandingIDs: Set(outstanding.map(\.id)))

        await SubmissionBadgeStore.shared.refresh()

        lastSyncResult = SyncResult(
            gamesPushed: pushedOutstanding.pushed,
            pendingCount: SubmissionBadgeStore.shared.pendingCount,
            errors: pushedOutstanding.errors,
            skippedNoOpenRound: pushedOutstanding.skippedNoOpenRound,
            retriedOutstanding: pushedOutstanding.retried
        )
        lastSyncedAt = Date()
    }

    /// App-foreground/launch hook: retries every game with an unconfirmed
    /// push, without requiring the manager to open the sync picker. Same
    /// outbox mechanism as the sweep inside `sync()` above, just without an
    /// explicit selection driving it. Silent on success (no result surfaced)
    /// — a manager-initiated `sync()` is what shows a summary; this just
    /// clears the backlog quietly in the background.
    func retryOutstanding(context: ModelContext) async {
        guard !isSyncing else { return }
        let pwaSubmissionsEnabled = UserDefaults.standard.bool(forKey: "pwaSubmissionsEnabled")
        guard Entitlements.shared.canUseCloud, pwaSubmissionsEnabled else { return }

        let outstanding = ((try? context.fetch(FetchDescriptor<Game>())) ?? []).filter { $0.pushPending }
        guard !outstanding.isEmpty else { return }

        isSyncing = true
        defer { isSyncing = false }
        let managerName = UserDefaults.standard.string(forKey: ManagerSettings.nameKey) ?? ""
        _ = await pushGames(outstanding, managerName: managerName, context: context, outstandingIDs: Set(outstanding.map(\.id)))
        await SubmissionBadgeStore.shared.refresh()
    }

    /// Shared push loop for `sync()` and `retryOutstanding()`. `outstandingIDs`
    /// marks which of `games` are being retried rather than freshly selected
    /// — those use `.all` scope rather than `.forRoundPush`, since a retry
    /// can't tell whether the write that never confirmed was a full-roster
    /// push or a single-player mint/rename/add-to-game push; `.all` is the
    /// one scope guaranteed to cover either case (always safe — every write
    /// here is an idempotent upsert on a natural key).
    private func pushGames(
        _ games: [Game], managerName: String, context: ModelContext, outstandingIDs: Set<UUID>
    ) async -> PushGamesOutcome {
        var pushed = 0
        var retried = 0
        var errors: [SyncGameError] = []
        var skippedNoOpenRound: [String] = []

        for game in games {
            guard let openRound = game.rounds.first(where: { $0.status == .open }) else {
                skippedNoOpenRound.append(game.name)
                continue
            }
            let isRetry = outstandingIDs.contains(game.id)
            let scope: PWAPlayerScope = isRetry ? .all : .forRoundPush(game: game)
            do {
                switch game.mode {
                case .lms, .predictor:
                    try await PWARoundPusher.pushLMSOrPredictor(
                        game: game, round: openRound, managerName: managerName, context: context, scope: scope
                    )
                case .killer:
                    try await PWARoundPusher.pushKiller(
                        game: game, round: openRound, managerName: managerName, context: context, scope: scope
                    )
                }
                pushed += 1
                if isRetry { retried += 1 }
            } catch {
                syncLog.warning("Sync push failed for \(game.name): \(error.localizedDescription)")
                errors.append(SyncGameError(gameName: game.name, message: error.localizedDescription))
            }
        }
        return PushGamesOutcome(pushed: pushed, retried: retried, errors: errors, skippedNoOpenRound: skippedNoOpenRound)
    }
}
