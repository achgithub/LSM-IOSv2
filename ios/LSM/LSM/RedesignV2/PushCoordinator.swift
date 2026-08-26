import Foundation
import Observation
import OSLog
import SwiftData

private let pushLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "lsm", category: "submissions")

/// One game's push failure, surfaced in the post-push summary rather than
/// aborting the rest of the push.
struct PushGameError: Identifiable {
    let id = UUID()
    let gameName: String
    let message: String
}

/// Outcome of the most recent `PushCoordinator.push()` call — mirrors
/// Clubroom2's `SyncResult` shape (push count + pull count + per-item
/// failures), adapted to this app's games/submissions.
struct PushResult {
    let gamesPushed: Int
    let pendingCount: Int
    let errors: [PushGameError]
    /// Games with no open round, so nothing was pushed for them — surfaced
    /// separately from `errors` since it isn't a failure, but a manager
    /// still needs to know: until a round opens and a push goes out, that
    /// game's player link isn't live yet.
    let skippedNoOpenRound: [String]
    /// Of `gamesPushed`, how many were retried because a *previous* push
    /// never confirmed (`Game.pushPending`), not because the manager picked
    /// them this time — the client-side outbox. Surfaced separately so a
    /// retry-driven push to an unselected game is visible, not silent.
    let retriedOutstanding: Int

    /// Brief post-push summary ("3 games pushed, 2 pending submissions"),
    /// surfacing errors instead of the pending count when any game failed.
    /// Shared by every entry point into `PushCoordinator.push` (currently
    /// just Games' PUSH tile — see that screen's doc comment on why Home's
    /// no longer has one of its own) so the manager sees the same feedback
    /// regardless of where they tapped from.
    var summaryText: String {
        let gamesPart = gamesPushed == 1 ? "1 game pushed" : "\(gamesPushed) games pushed"
        let skippedPart: String = {
            guard !skippedNoOpenRound.isEmpty else { return "" }
            let count = skippedNoOpenRound.count
            return count == 1 ? ", 1 waiting for a round" : ", \(count) waiting for a round"
        }()
        let retriedPart: String = {
            guard retriedOutstanding > 0 else { return "" }
            return retriedOutstanding == 1 ? ", 1 retried" : ", \(retriedOutstanding) retried"
        }()
        if errors.isEmpty {
            let pendingPart = pendingCount == 1 ? "1 pending submission" : "\(pendingCount) pending submissions"
            return "\(gamesPart), \(pendingPart)\(skippedPart)\(retriedPart)"
        } else {
            let errorPart = errors.count == 1 ? "1 game failed" : "\(errors.count) games failed"
            return "\(gamesPart) — \(errorPart)\(skippedPart)\(retriedPart)"
        }
    }
}

/// Return shape for `PushCoordinator.pushGames` — everything `PushResult`
/// needs except `pendingCount`, which only `push()`/`retryOutstanding()`
/// know how to fetch (via `SubmissionBadgeStore`) after the push loop ends.
private struct PushGamesOutcome {
    let pushed: Int
    let retried: Int
    let errors: [PushGameError]
    let skippedNoOpenRound: [String]
}

/// Unified "push to players" action, **RedesignV2 only**: sends the open
/// round of every game the manager explicitly picks in `PushGamePickerViewV2`
/// (across LMS/Predictor/Killer) to the Player App and refreshes the
/// pending-submission count, replacing what today is three separate manual
/// flows (per-game "Resend to Player App", pull-to-refresh inside the
/// submission queue, and — unaffected here — approve/reject). V1 keeps its
/// existing per-game flows exactly as they are (`SubmissionQueueView`, each
/// mode's `resend()`); this is not retrofitted there.
///
/// Named `PushCoordinator`, not `SyncCoordinator` — deliberately, after the
/// two collided. "Sync" is already the app's word for cloud game recovery
/// (`GameSyncClient`/`GameSyncListModel`, surfaced on `ProfileSettingsViewV2`
/// as "bring a game to this device"), a genuinely different operation this
/// type has nothing to do with. This one only ever moves data toward the
/// PWA and refreshes what's pending there — "push" is the accurate verb, and
/// keeps the two apart in code, comments and UI copy alike.
///
/// Singleton, injected once at the app root alongside `SubmissionBadgeStore`
/// (see `RootTabView`), same `@Observable @MainActor` shape so every V2
/// screen reads the same live push state.
///
/// Explicitly does **not** auto-approve anything — approve/reject stays a
/// manual per-submission decision in `SubmissionInboxViewV2`. Push only
/// sends open rounds and refreshes visibility of what's pending.
@Observable @MainActor
final class PushCoordinator {
    static let shared = PushCoordinator()

    private(set) var isPushing = false
    private(set) var lastPushedAt: Date?
    private(set) var lastPushResult: PushResult?
    /// True for a few seconds after a manager-initiated `push()` completes —
    /// drives the post-push summary card every entry point shares (see
    /// `PushResult.summaryText` and `View.v2PushSummary`). Not set by
    /// `retryOutstanding()`'s silent background sweep.
    private(set) var showSummary = false

    private init() {}

    /// Pushes every **selected** game (any mode) that currently has an open
    /// round, reusing the *existing* per-game push logic in `PWARoundPusher`
    /// (`pushLMSOrPredictor`/`pushKiller`) — no new push implementation.
    /// `gameIDs` is required, not defaulted to "all games": every call site
    /// goes through `PushGamePickerViewV2` so a manager explicitly picks
    /// which games to push each time, rather than a stray tap fanning out
    /// a network call per game — each push is a billed Worker invocation, so
    /// an unfiltered "push everything" button was a standing cost risk with
    /// more than a couple of games running (there's deliberately no
    /// select-all shortcut in the picker either, for the same reason).
    /// Failures are collected per-game rather than aborting the whole push on
    /// one bad game. Once every push has settled, refreshes
    /// `SubmissionBadgeStore` so the pending count reflects whatever the
    /// pushes just made visible (subject to the backend's own ≤60s KV
    /// propagation window — the summary reads as "as of now", not exact).
    func push(context: ModelContext, gameIDs: Set<UUID>) async {
        guard !isPushing, !gameIDs.isEmpty else { return }
        isPushing = true
        defer { isPushing = false }

        let managerName = UserDefaults.standard.string(forKey: ManagerSettings.nameKey) ?? ""
        let pwaSubmissionsEnabled = UserDefaults.standard.bool(forKey: "pwaSubmissionsEnabled")
        guard Entitlements.shared.canUseCloud, pwaSubmissionsEnabled else {
            // Cloud submissions off (or unavailable at this tier) — nothing to
            // push, but still worth refreshing the badge in case tier/toggle
            // changed since the last look.
            await SubmissionBadgeStore.shared.refresh()
            lastPushResult = PushResult(gamesPushed: 0, pendingCount: SubmissionBadgeStore.shared.pendingCount, errors: [], skippedNoOpenRound: [], retriedOutstanding: 0)
            lastPushedAt = Date()
            presentSummary()
            return
        }

        let allGames = (try? context.fetch(FetchDescriptor<Game>())) ?? []
        let selected = allGames.filter { gameIDs.contains($0.id) }
        // Writes this device already attempted and never got confirmation
        // for (`Game.pushPending`) — the client-side outbox. Retried
        // alongside the explicit selection even when not picked this time:
        // bounded by what this device already tried, not an open-ended
        // resync, so it doesn't undermine the "manager picks what pushes"
        // design above. Excludes anything already in `selected` to avoid a
        // double push.
        let outstanding = allGames.filter { $0.pushPending && !gameIDs.contains($0.id) }

        let pushedOutstanding = await pushGames(selected + outstanding, managerName: managerName, context: context, outstandingIDs: Set(outstanding.map(\.id)))

        await SubmissionBadgeStore.shared.refresh()

        lastPushResult = PushResult(
            gamesPushed: pushedOutstanding.pushed,
            pendingCount: SubmissionBadgeStore.shared.pendingCount,
            errors: pushedOutstanding.errors,
            skippedNoOpenRound: pushedOutstanding.skippedNoOpenRound,
            retriedOutstanding: pushedOutstanding.retried
        )
        lastPushedAt = Date()
        presentSummary()
    }

    /// Shows the summary card for a few seconds, then hides it again — see
    /// `showSummary`. Both branches of `push()` call this so a manager gets
    /// the same feedback whether or not there was anything to push (see V2
    /// audit 1.1: before this was factored out, Home's tile called `push`
    /// directly and skipped this step entirely, so it silently completed).
    private func presentSummary() {
        showSummary = true
        Task {
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            showSummary = false
        }
    }

    /// One-time backfill, run once ever on first launch after this shipped:
    /// `round_pushes.game_config_json` (added for per-game sync — see
    /// `GameConfigPayload`) only exists for games pushed *after* the column
    /// existed, so every game already in the cloud from before needs one
    /// more push to pick it up. Rather than a dedicated endpoint/call path,
    /// this piggybacks on the outbox that already exists: flag every
    /// eligible game as `pushPending` (same flag a dropped-connection retry
    /// uses) and let the very next `retryOutstanding()` call — already
    /// scheduled at every launch, see `RootTabView` — resend them through
    /// the normal push path, which now always includes `gameConfigJSON`.
    /// Only games with an open round are flagged, matching `pushGames`'s
    /// own skip condition, so nothing is left permanently stuck pending.
    /// Games with no cloud token yet have nothing to backfill (their first
    /// push, whenever it happens, already carries config).
    private static let configBackfillSweptKey = "gameConfigBackfillSweptV1"

    func backfillGameConfigIfNeeded(context: ModelContext) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.configBackfillSweptKey) else { return }
        let allGames = (try? context.fetch(FetchDescriptor<Game>())) ?? []
        for game in allGames where game.cloudGameTokenRaw != nil && game.rounds.contains(where: { $0.status == .open }) {
            game.pushPending = true
        }
        defaults.set(true, forKey: Self.configBackfillSweptKey)
    }

    /// App-foreground/launch hook: retries every game with an unconfirmed
    /// push, without requiring the manager to open the push picker. Same
    /// outbox mechanism as the sweep inside `push()` above, just without an
    /// explicit selection driving it. Silent on success (no result surfaced,
    /// no summary card) — a manager-initiated `push()` is what shows one;
    /// this just clears the backlog quietly in the background.
    func retryOutstanding(context: ModelContext) async {
        guard !isPushing else { return }
        let pwaSubmissionsEnabled = UserDefaults.standard.bool(forKey: "pwaSubmissionsEnabled")
        guard Entitlements.shared.canUseCloud, pwaSubmissionsEnabled else { return }

        let outstanding = ((try? context.fetch(FetchDescriptor<Game>())) ?? []).filter { $0.pushPending }
        guard !outstanding.isEmpty else { return }

        isPushing = true
        defer { isPushing = false }
        let managerName = UserDefaults.standard.string(forKey: ManagerSettings.nameKey) ?? ""
        _ = await pushGames(outstanding, managerName: managerName, context: context, outstandingIDs: Set(outstanding.map(\.id)))
        await SubmissionBadgeStore.shared.refresh()
    }

    /// Shared push loop for `push()` and `retryOutstanding()`. `outstandingIDs`
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
        var errors: [PushGameError] = []
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
                pushLog.warning("Push failed for \(game.name): \(error.localizedDescription)")
                errors.append(PushGameError(gameName: game.name, message: error.localizedDescription))
            }
        }
        if retried > 0 {
            // Per-game "outbox cleared"/"outbox queued" lines already come
            // from PWARoundPusher itself — this is the summary, useful
            // mainly for retryOutstanding()'s silent app-launch sweep, which
            // otherwise leaves no trace anywhere a manager could check.
            await DiagnosticLog.shared.log("outbox sweep retried \(retried) game(s)", category: "submissions")
        }
        return PushGamesOutcome(pushed: pushed, retried: retried, errors: errors, skippedNoOpenRound: skippedNoOpenRound)
    }
}
