import Foundation

/// Matches data + refresh-throttle logic for `MatchesViewV2`, modeled
/// directly on `StandingsStore`'s shape. Mirrors `MatchesView`'s own
/// refresh()/load() logic verbatim (three-branch ad-gate, shared throttle
/// clock) so the two screens stay correctly cross-throttled — Results
/// entry's "Pull results from server" reads/writes the same per-league
/// Matches cache as both of these.
@Observable
final class MatchesStoreV2 {
    var items: [MatchDTO] = []
    var teamsById: [Int: TeamDTO] = [:]
    var isLoading = false
    var errorMessage: String?
    var lastRefreshed: Date?
    var freshUntil: Date?
    /// Ticked every second by the view's `Timer.publish` while throttled —
    /// see `MatchesViewV2`'s `.onReceive`. Settable (not `private(set)`) for
    /// exactly that; a one-shot sleep-then-set-once left the countdown
    /// frozen on screen between arm and expiry.
    var now = Date()

    var isThrottled: Bool { freshUntil.map { now < $0 } ?? false }

    private func matchesThrottleUntil(leagues: [LeagueOption]) -> Date? {
        LeagueDataCache.sharedMatchesThrottleUntil(for: leagues.map(\.id))
    }

    /// `force` (the ad-gated refresh) always hits the network and overwrites
    /// the per-league cache; otherwise each league is served purely from its
    /// cache — identical semantics to `MatchesView.load(force:)`.
    func load(leagues: [LeagueOption], force: Bool = false) async {
        isLoading = true
        errorMessage = nil
        var allItems: [MatchDTO] = []
        var dates: [Date] = []
        do {
            for league in leagues {
                let key = LeagueDataCache.matchesKey(league.id)
                if !force, let cached = LeagueDataCache.load(LeagueDataCache.Matches.self, key: key) {
                    allItems += cached.items
                    dates.append(cached.date)
                } else if force {
                    let leagueItems = try await LeagueData.pullLiveMatches(for: league)
                    allItems += leagueItems
                    dates.append(Date())
                }
            }
            // Fetch team names before publishing `items` — same ordering
            // rationale as MatchesView.load: avoids a "Team <id>" flash.
            let teams = (try? await LeagueData.load(for: leagues))?.teamsById ?? teamsById
            items = allItems
            teamsById = teams
            lastRefreshed = dates.max()
        } catch {
            errorMessage = error.localizedDescription
        }
        now = Date()
        freshUntil = matchesThrottleUntil(leagues: leagues)
        isLoading = false
    }
}
