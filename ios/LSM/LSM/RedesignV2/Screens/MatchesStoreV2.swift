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
    private(set) var now = Date()

    var isThrottled: Bool { freshUntil.map { now < $0 } ?? false }

    func armClock() async {
        guard let freshUntil else { return }
        let remaining = freshUntil.timeIntervalSinceNow
        if remaining > 0 { try? await Task.sleep(for: .seconds(remaining)) }
        now = Date()
    }

    private func matchesThrottleUntil(leagues: [LeagueOption]) -> Date? {
        LeagueDataCache.sharedMatchesThrottleUntil(for: leagues.map(\.id))
    }

    /// Refresh button. Honours the local TTL (Rule A) and self-heals
    /// corruption, identically to `MatchesView.refresh()`:
    /// - every league fresh within TTL → re-show cache, no ad, no call;
    /// - any corrupt cache → recover with a free fetch;
    /// - otherwise (any stale/empty) → the normal ad-gated fetch.
    func refresh(leagues: [LeagueOption]) {
        var anyCorrupt = false
        var allFresh = true
        for league in leagues {
            switch LeagueDataCache.read(LeagueDataCache.Matches.self, key: LeagueDataCache.matchesKey(league.id)) {
            case .hit(let cached):
                if !LeagueDataCache.isFresh(cached.date, ttl: CacheTTL.matches) { allFresh = false }
            case .empty:
                allFresh = false
            case .corrupt:
                allFresh = false
                anyCorrupt = true
            }
        }
        if allFresh {
            Task { await load(leagues: leagues) }
        } else if anyCorrupt {
            Task { await load(leagues: leagues, force: true) }
        } else {
            AdGate.run { [weak self] in Task { await self?.load(leagues: leagues, force: true) } }
        }
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
