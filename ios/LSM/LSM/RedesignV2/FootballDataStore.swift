import Foundation

/// Home screen's combined "Update football data" action — refreshes every
/// enabled league's matches AND standings together in one tap, gated behind
/// one shared throttle. Deliberately separate from `PushCoordinator`: Push
/// sends a manager's own game rounds and player submissions to the PWA;
/// this refreshes the football provider data (fixtures/scores/tables) those
/// rounds are built from. A manager can hit either without the other
/// implying it.
///
/// Runs on its own 10-minute cooldown (`CacheTTL.updateFootballDataThrottle`)
/// — deliberately private to this button, not the shared 2-minute
/// (`CacheTTL.matches`) clock the Fixtures tab and Results entry's "pull
/// results" share, since this is Manage Leagues' one manual sync-everything
/// action, not a per-screen live-scores pull. Standings has its own, much
/// longer 30-minute TTL (`CacheTTL.standings`) when refreshed from the
/// Standings tab; this button intentionally ignores that and force-refreshes
/// standings on the same cadence as matches, since this is one unified
/// action behind its own cooldown, not the per-screen Standings refresh.
@Observable
final class FootballDataStore {
    /// Persists `freshUntil` across store instances — the store itself is
    /// `@State` on `LeaguesPortalViewV2`, so it's recreated from scratch
    /// every time that screen is pushed to again, which used to silently
    /// reset the cooldown (leave, come back, SYNC looks available again
    /// even mid-throttle).
    private static let freshUntilKey = "footballDataStore.freshUntil"

    var isLoading = false
    var errorMessage: String?
    var lastRefreshed: Date?
    var freshUntil: Date? {
        didSet { UserDefaults.standard.set(freshUntil, forKey: Self.freshUntilKey) }
    }
    /// Ticked every second by the view's `Timer.publish` while throttled —
    /// see `FootballDataCard`'s `.onReceive`. Settable (not `private(set)`)
    /// for exactly that; a one-shot sleep-then-set-once left the countdown
    /// frozen on screen between arm and expiry.
    var now = Date()

    init() {
        freshUntil = UserDefaults.standard.object(forKey: Self.freshUntilKey) as? Date
    }

    var isThrottled: Bool { freshUntil.map { now < $0 } ?? false }

    /// "4M" while throttled, counting down as `now` ticks — `nil` once the
    /// cooldown lapses. Lets the SYNC tile explain *why* it's greyed out
    /// instead of just going dim with no feedback.
    var throttleRemainingLabel: String? {
        guard let freshUntil, now < freshUntil else { return nil }
        let minutes = Int((freshUntil.timeIntervalSince(now) / 60).rounded(.up))
        return "\(max(minutes, 1))M"
    }

    /// Ad-gated for free users (skipped entirely for subscribers via
    /// `AdGate`); the 2-minute cooldown applies to everyone regardless of
    /// tier, so it can't be hammered by repeatedly dismissing/re-watching ads.
    /// Also guards `isLoading` directly (not just relying on the caller's
    /// button being disabled) — the SYNC tile no longer marks itself
    /// `.disabled` while loading, since SwiftUI auto-dims disabled content
    /// in a way that made the throttle countdown unreadable.
    func refresh(leagues: [LeagueOption]) {
        guard !isThrottled, !isLoading else { return }
        AdGate.run { [weak self] in Task { await self?.load(leagues: leagues) } }
    }

    private func load(leagues: [LeagueOption]) async {
        let targets = leagues.isEmpty ? [Leagues.home] : leagues
        isLoading = true
        errorMessage = nil
        var anySucceeded = false
        for league in targets {
            if (try? await LeagueData.pullLiveMatches(for: league)) != nil { anySucceeded = true }
        }
        await LeagueData.refreshStandings(for: targets)
        if anySucceeded {
            lastRefreshed = Date()
        } else {
            errorMessage = "Couldn't reach the server."
        }
        now = Date()
        freshUntil = Date().addingTimeInterval(CacheTTL.updateFootballDataThrottle)
        isLoading = false
    }
}
