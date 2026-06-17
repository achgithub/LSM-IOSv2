import Foundation

/// A snapshot of the provider data the round-flow screens need, fetched together.
/// Supports one or several leagues at once (a game can blend leagues): the
/// fixtures/teams/standings of every league are merged. football-data team and
/// fixture ids are globally unique, so merging by id is safe.
///
/// Every resource is served **cache-first** so that running rounds never spams
/// the Worker and never silently hands a free user fresh data:
/// - **Teams / fixtures** (functional, free) refresh from the Worker only once
///   their local TTL (`CacheTTL`) lapses; otherwise the on-disk snapshot is used.
/// - **Standings** (the table — gated) is *only ever read from cache* here, so
///   opening Picks/Results can't be a free table refresh. The sole exception is
///   an empty/corrupt cache, which gets one free fill (first-install rule). The
///   gated refresh lives elsewhere (Standings tab, or the auto-assign prompt via
///   `refreshStandings`).
struct LeagueData {
    let fixtures: [FixtureDTO]
    let teamsById: [Int: TeamDTO]
    let standingsByTeam: [Int: StandingDTO]
    /// teamId → its league's team count (so weak-pick is correct across a blend).
    let teamsCountByTeam: [Int: Int]
    /// teamId → leagueId, to resolve which league a team/fixture belongs to.
    let leagueIdByTeam: [Int: String]
    /// Age marker for the table: the **oldest** standings snapshot across the
    /// game's leagues (nil only if a league had no table at all). Drives the
    /// auto-assign staleness prompt.
    let standingsDate: Date?

    /// Load and merge data for a set of leagues (a game's leagues).
    /// - Parameter forceFixtures: bypass the fixtures TTL and pull fresh fixtures
    ///   from the Worker. Used by the ad-gated "pull results from server" action,
    ///   where the whole point is genuinely fresh results.
    static func load(for leagues: [LeagueOption], forceFixtures: Bool = false) async throws -> LeagueData {
        let targets = leagues.isEmpty ? [Leagues.home] : leagues

        var fixtures: [FixtureDTO] = []
        var teamsById: [Int: TeamDTO] = [:]
        var standingsByTeam: [Int: StandingDTO] = [:]
        var teamsCountByTeam: [Int: Int] = [:]
        var leagueIdByTeam: [Int: String] = [:]
        var oldestStandings: Date?

        // 1–3 leagues typically, so a sequential merge is fine.
        for league in targets {
            let teams = try await cachedTeams(for: league)
            let f = try await cachedFixtures(for: league, force: forceFixtures)
            let (rows, date) = try await cachedStandings(for: league, teams: teams)

            fixtures.append(contentsOf: f)
            for team in teams {
                teamsById[team.externalId] = team
                teamsCountByTeam[team.externalId] = league.teamsCount
                leagueIdByTeam[team.externalId] = league.id
            }
            for standing in rows { standingsByTeam[standing.teamId] = standing }
            if let date { oldestStandings = min(oldestStandings ?? date, date) }
        }

        return LeagueData(
            fixtures: fixtures,
            teamsById: teamsById,
            standingsByTeam: standingsByTeam,
            teamsCountByTeam: teamsCountByTeam,
            leagueIdByTeam: leagueIdByTeam,
            standingsDate: oldestStandings
        )
    }

    /// Convenience for a single league.
    static func load(for league: LeagueOption, forceFixtures: Bool = false) async throws -> LeagueData {
        try await load(for: [league], forceFixtures: forceFixtures)
    }

    /// Gated, forced refresh of the league table(s) — fetches fresh standings from
    /// the Worker and overwrites the per-league cache that `cachedStandings` (and
    /// the Standings tab) read. Call from behind `AdGate`. Best-effort per league:
    /// a league that fails to refresh keeps its previous cached table.
    static func refreshStandings(for leagues: [LeagueOption]) async {
        for league in (leagues.isEmpty ? [Leagues.home] : leagues) {
            let client = league.client
            guard let rows = try? await client.standings(),
                  let teams = try? await client.teams() else { continue }
            LeagueDataCache.save(
                LeagueDataCache.Standings(date: Date(), rows: rows, teams: teams),
                key: LeagueDataCache.standingsKey(league.id)
            )
        }
    }

    // MARK: - Per-resource cache-first loaders

    /// Teams: functional/free. Served from cache within its TTL; otherwise fetched
    /// and re-cached. On a fetch failure with any cached copy, the stale copy is
    /// used rather than failing the whole load.
    private static func cachedTeams(for league: LeagueOption) async throws -> [TeamDTO] {
        let key = LeagueDataCache.teamsKey(league.id)
        switch LeagueDataCache.read(LeagueDataCache.Teams.self, key: key) {
        case .hit(let cached) where LeagueDataCache.isFresh(cached.date, ttl: CacheTTL.teams):
            return cached.items
        case .hit(let cached):
            return (try? await fetchTeams(league, key: key)) ?? cached.items
        case .empty, .corrupt:
            return try await fetchTeams(league, key: key)
        }
    }

    private static func fetchTeams(_ league: LeagueOption, key: String) async throws -> [TeamDTO] {
        let teams = try await league.client.teams()
        LeagueDataCache.save(LeagueDataCache.Teams(date: Date(), items: teams), key: key)
        return teams
    }

    /// Fixtures: functional/free. Cache-first within TTL unless `force` (the
    /// ad-gated results pull) demands fresh. Falls back to a stale copy on a fetch
    /// failure when one exists.
    private static func cachedFixtures(for league: LeagueOption, force: Bool) async throws -> [FixtureDTO] {
        let key = LeagueDataCache.fixturesKey(league.id)
        let cached = LeagueDataCache.load(LeagueDataCache.Fixtures.self, key: key)
        if !force, let cached, LeagueDataCache.isFresh(cached.date, ttl: CacheTTL.fixtures) {
            return cached.items
        }
        do {
            let fixtures = try await league.client.fixtures()
            LeagueDataCache.save(LeagueDataCache.Fixtures(date: Date(), items: fixtures), key: key)
            return fixtures
        } catch {
            if let cached { return cached.items }
            throw error
        }
    }

    /// Standings (the table — gated): read from cache **only**, regardless of age,
    /// so a round-flow open is never a free table refresh. The staleness prompt /
    /// gated refresh handles freshness. An empty or corrupt cache gets one free
    /// fill (first-install rule), writing the same cache the Standings tab uses.
    private static func cachedStandings(
        for league: LeagueOption,
        teams: [TeamDTO]
    ) async throws -> ([StandingDTO], Date?) {
        let key = LeagueDataCache.standingsKey(league.id)
        if case .hit(let cached) = LeagueDataCache.read(LeagueDataCache.Standings.self, key: key) {
            return (cached.rows, cached.date)
        }
        // Empty or corrupt → free first fill (reusing the teams we already loaded).
        let rows = try await league.client.standings()
        let now = Date()
        LeagueDataCache.save(LeagueDataCache.Standings(date: now, rows: rows, teams: teams), key: key)
        return (rows, now)
    }
}
