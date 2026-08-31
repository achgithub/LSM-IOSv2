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
    var isLoading = false
    var errorMessage: String?
    var lastRefreshed: Date?
    var freshUntil: Date?
    /// Ticked every second by the view's `Timer.publish` while throttled —
    /// see `FootballDataCard`'s `.onReceive`. Settable (not `private(set)`)
    /// for exactly that; a one-shot sleep-then-set-once left the countdown
    /// frozen on screen between arm and expiry.
    var now = Date()

    var isThrottled: Bool { freshUntil.map { now < $0 } ?? false }

    /// Ad-gated for free users (skipped entirely for subscribers via
    /// `AdGate`); the 2-minute cooldown applies to everyone regardless of
    /// tier, so it can't be hammered by repeatedly dismissing/re-watching ads.
    func refresh(leagues: [LeagueOption]) {
        guard !isThrottled else { return }
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
