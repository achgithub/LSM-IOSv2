import Foundation

/// Standings data + refresh-throttle logic (Rule A), shared by the classic
/// List-based `StandingsView` and the card-based `StandingsViewV2` — kept in
/// one place so both stay correct as the UI is redesigned in parallel.
@Observable
final class StandingsStore {
    var standings: [StandingDTO] = []
    var teamsById: [Int: TeamDTO] = [:]
    var isLoading = false
    var errorMessage: String?
    var lastRefreshed: Date?
    var freshUntil: Date?
    private(set) var now = Date()

    /// True while the table is fresh within its 30m TTL — the refresh button
    /// should be greyed out during this window.
    var isThrottled: Bool { freshUntil.map { now < $0 } ?? false }

    /// Sleeps until `freshUntil` lapses, then flips `isThrottled` off via
    /// `now`. Re-run this as `.task(id: freshUntil)` so it re-arms whenever
    /// the deadline changes (and fires immediately if it already passed).
    func armClock() async {
        guard let freshUntil else { return }
        let remaining = freshUntil.timeIntervalSinceNow
        if remaining > 0 { try? await Task.sleep(for: .seconds(remaining)) }
        now = Date()
    }

    private func throttleUntil(league: LeagueOption) -> Date? {
        switch LeagueDataCache.read(LeagueDataCache.Standings.self, key: LeagueDataCache.standingsKey(league.id)) {
        case .hit(let cached) where LeagueDataCache.isFresh(cached.date, ttl: CacheTTL.standings):
            return cached.date.addingTimeInterval(CacheTTL.standings)
        case .hit, .empty, .corrupt:
            return nil
        }
    }

    /// Refresh button. Honours the local TTL (Rule A) and self-heals
    /// corruption:
    /// - fresh within TTL → re-show cache, **no ad, no Worker call**;
    /// - corrupt cache → recover with a **free** fetch (our bad data, not a
    ///   paid refresh) — `read` has already deleted the bad file;
    /// - stale / empty → the normal ad-gated fetch.
    func refresh(league: LeagueOption) {
        let key = LeagueDataCache.standingsKey(league.id)
        switch LeagueDataCache.read(LeagueDataCache.Standings.self, key: key) {
        case .hit(let cached) where LeagueDataCache.isFresh(cached.date, ttl: CacheTTL.standings):
            teamsById = Dictionary(cached.teams.map { ($0.externalId, $0) }, uniquingKeysWith: { first, _ in first })
            standings = StandingDTO.displayOrder(rows: cached.rows, teamsById: teamsById)
            lastRefreshed = cached.date
        case .corrupt:
            Task { await load(league: league, force: true) }
        case .hit, .empty:
            AdGate.run { [weak self] in Task { await self?.load(league: league, force: true) } }
        }
    }

    /// V2-only: pure cache read, no fallback network call on an empty/corrupt
    /// cache — `SyncScheduler` (app foreground + the live-poll loop) is V2's
    /// sole source of truth for keeping this cache warm, so this screen
    /// shouldn't silently hit the Worker on its own just because it appeared.
    /// If the cache is missing, corrupt, or older than
    /// `CacheTTL.standingsStaleCeiling` (12h), triggers a normal ad-gated
    /// refresh instead of leaving a silently-stale (or forever-empty) table
    /// on screen — e.g. a league enabled after first launch, or a device
    /// that's been off `SyncScheduler`'s ladder (Free tier, or simply not
    /// opened) for a long stretch.
    func loadFromCache(league: LeagueOption) async {
        isLoading = standings.isEmpty
        errorMessage = nil
        let key = LeagueDataCache.standingsKey(league.id)
        switch LeagueDataCache.read(LeagueDataCache.Standings.self, key: key) {
        case .hit(let cached):
            teamsById = Dictionary(cached.teams.map { ($0.externalId, $0) }, uniquingKeysWith: { first, _ in first })
            standings = StandingDTO.displayOrder(rows: cached.rows, teamsById: teamsById)
            lastRefreshed = cached.date
            freshUntil = throttleUntil(league: league)
            isLoading = false
            if !LeagueDataCache.isFresh(cached.date, ttl: CacheTTL.standingsStaleCeiling) {
                AdGate.run { [weak self] in Task { await self?.load(league: league, force: true) } }
            }
        case .empty, .corrupt:
            isLoading = false
            AdGate.run { [weak self] in Task { await self?.load(league: league, force: true) } }
        }
    }

    /// `force` (the ad-gated refresh) hits the network and overwrites the
    /// cache; otherwise the league is served from its cache, fetching only
    /// the first time (empty/corrupt cache) — so a relaunch isn't a free
    /// refresh.
    func load(league: LeagueOption, force: Bool) async {
        isLoading = true
        errorMessage = nil
        let key = LeagueDataCache.standingsKey(league.id)
        if !force, let cached = LeagueDataCache.load(LeagueDataCache.Standings.self, key: key) {
            teamsById = Dictionary(cached.teams.map { ($0.externalId, $0) }, uniquingKeysWith: { first, _ in first })
            standings = StandingDTO.displayOrder(rows: cached.rows, teamsById: teamsById)
            lastRefreshed = cached.date
            freshUntil = throttleUntil(league: league)
            isLoading = false
            return
        }
        let client = league.client
        do {
            async let standingsReq = client.standings()
            async let teamsReq = client.teams()
            let (rows, teams) = try await (standingsReq, teamsReq)
            teamsById = Dictionary(teams.map { ($0.externalId, $0) }, uniquingKeysWith: { first, _ in first })
            standings = StandingDTO.displayOrder(rows: rows, teamsById: teamsById)
            let fetchedAt = Date()
            lastRefreshed = fetchedAt
            LeagueDataCache.save(LeagueDataCache.Standings(date: fetchedAt, rows: rows, teams: teams), key: key)
        } catch {
            errorMessage = error.localizedDescription
        }
        freshUntil = throttleUntil(league: league)
        isLoading = false
    }
}
