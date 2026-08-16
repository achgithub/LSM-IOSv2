import Foundation

/// Home screen's combined "Update football data" action — refreshes every
/// enabled league's matches AND standings together in one tap, gated behind
/// one shared throttle. Deliberately separate from `SyncCoordinator`: Sync
/// pushes/pulls a manager's own game rounds and player submissions; this
/// refreshes the football provider data (fixtures/scores/tables) those
/// rounds are built from. A manager can hit either without the other
/// implying it.
///
/// Reuses `LeagueDataCache.sharedMatchesThrottleUntil` — the same cross-
/// screen 2-minute (`CacheTTL.matches`) clock the Fixtures tab and Results
/// entry's "pull results" already share — rather than a clock private to
/// this button, so tapping Update here and then opening Fixtures right after
/// doesn't present a second ad for data that was just fetched. Standings has
/// its own, much longer 30-minute TTL (`CacheTTL.standings`) when refreshed
/// from its own screen; this button intentionally ignores that and force-
/// refreshes standings on the same 2-minute cadence as matches, since this
/// is one unified action behind its own cooldown, not the per-screen
/// Standings refresh.
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
        freshUntil = LeagueDataCache.sharedMatchesThrottleUntil(for: targets.map(\.id))
        isLoading = false
    }
}
