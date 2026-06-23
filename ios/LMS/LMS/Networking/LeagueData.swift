import Foundation

/// A snapshot of the provider data the round-flow screens need, fetched together.
/// Supports one or several leagues at once (a game can blend leagues): the
/// matches/teams/standings of every league are merged. football-data team and
/// match ids are globally unique, so merging by id is safe.
///
/// Every resource is served **cache-first** so that running rounds never spams
/// the Worker and never silently hands a free user fresh data:
/// - **Teams** (functional, free) refreshes from the Worker only once its local
///   TTL (`CacheTTL`) lapses; otherwise the on-disk snapshot is used.
/// - **Matches and Standings** (the two gated products) are *only ever read
///   from cache* here — opening Open Round/Picks/Results is never a free
///   refresh of either. The single one-ever exception is a centralized,
///   explicit bootstrap at launch (`performFirstLaunchFreeFillIfNeeded`), not
///   anything lazy triggered from inside this load.
struct LeagueData {
    let matches: [MatchDTO]
    let teamsById: [Int: TeamDTO]
    let standingsByTeam: [Int: StandingDTO]
    /// teamId → its league's team count (so weak-pick is correct across a blend).
    let teamsCountByTeam: [Int: Int]
    /// Age marker for the table: the **oldest** standings snapshot across the
    /// game's leagues (nil only if a league had no table at all). Drives the
    /// auto-assign staleness prompt.
    let standingsDate: Date?
    /// Age marker for the schedule: the **oldest** Matches snapshot across the
    /// game's leagues (nil if a league has never been fetched at all). Drives
    /// the Fixtures-view courtesy prompt (`CacheTTL.fixturesCourtesyAge`).
    let matchesDate: Date?

    /// Load and merge data for a set of leagues (a game's leagues).
    static func load(for leagues: [LeagueOption]) async throws -> LeagueData {
        let targets = leagues.isEmpty ? [Leagues.home] : leagues

        var matches: [MatchDTO] = []
        var teamsById: [Int: TeamDTO] = [:]
        var standingsByTeam: [Int: StandingDTO] = [:]
        var teamsCountByTeam: [Int: Int] = [:]
        var oldestStandings: Date?
        var oldestMatches: Date?

        // 1–3 leagues typically, so a sequential merge is fine.
        for league in targets {
            let teams = try await cachedTeams(for: league)
            let (matchItems, matchDate) = cachedMatches(for: league)
            matches.append(contentsOf: matchItems)
            let (rows, date) = cachedStandings(for: league)

            for team in teams {
                teamsById[team.externalId] = team
                teamsCountByTeam[team.externalId] = league.teamsCount
            }
            for standing in rows { standingsByTeam[standing.teamId] = standing }
            if let date { oldestStandings = min(oldestStandings ?? date, date) }
            if let matchDate { oldestMatches = min(oldestMatches ?? matchDate, matchDate) }
        }

        return LeagueData(
            matches: matches,
            teamsById: teamsById,
            standingsByTeam: standingsByTeam,
            teamsCountByTeam: teamsCountByTeam,
            standingsDate: oldestStandings,
            matchesDate: oldestMatches
        )
    }

    /// Convenience for a single league.
    static func load(for league: LeagueOption) async throws -> LeagueData {
        try await load(for: [league])
    }

    /// Canonical "pull live data" for one league — the single gated action
    /// every screen that refreshes match info shares (Matches tab's refresh,
    /// the Fixtures-view courtesy prompt, Results entry's "Pull results from
    /// server"), so a manager is never asked to watch a rewarded ad twice for
    /// the same underlying fetch. Fetches /scores + /fixtures (NOT /teams —
    /// that has no live upstream path at all, see `cachedTeams`, so calling it
    /// here would only cost a Cloudflare invocation for data that's already as
    /// fresh as it'll ever be), merges them into one `MatchDTO` per match
    /// (schedule fields from /fixtures, live fields from /scores — the same
    /// merge `ScoreItem.init` used to do), and writes the single Matches
    /// cache. No more separate Fixtures cache to patch afterwards.
    static func pullLiveMatches(for league: LeagueOption) async throws -> [MatchDTO] {
        let client = league.client
        async let scoresReq = client.scores()
        async let fixturesReq = client.fixtures()
        let (scores, fixturesRaw) = try await (scoresReq, fixturesReq)

        let scoresById = Dictionary(scores.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let tagged = fixturesRaw.map { fixture -> MatchDTO in
            let score = scoresById[fixture.id]
            return MatchDTO(
                id: fixture.id,
                matchday: fixture.matchday,
                kickoff: fixture.kickoff,
                status: score?.status ?? fixture.status,
                minute: score?.minute,
                homeTeamId: fixture.homeTeamId,
                awayTeamId: fixture.awayTeamId,
                homeScore: score?.homeScore ?? fixture.homeScore,
                awayScore: score?.awayScore ?? fixture.awayScore,
                winner: score?.winner ?? fixture.winner,
                leagueId: league.id
            )
        }

        let key = LeagueDataCache.matchesKey(league.id)
        // Same empty-response guard as cachedTeams: a "blocked" league or a
        // transient upstream hiccup must never look like the cache just
        // emptied out. A network failure is handled separately, by the
        // caller's `try?`.
        if tagged.isEmpty, let existing = LeagueDataCache.load(LeagueDataCache.Matches.self, key: key) {
            return existing.items
        }
        LeagueDataCache.save(LeagueDataCache.Matches(date: Date(), items: tagged), key: key)
        return tagged
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
            // Same empty-response guard as cachedTeams — a "blocked" league
            // must keep its last real table, not show blank.
            if rows.isEmpty {
                let key = LeagueDataCache.standingsKey(league.id)
                if let existing = LeagueDataCache.load(LeagueDataCache.Standings.self, key: key), !existing.rows.isEmpty {
                    continue
                }
            }
            LeagueDataCache.save(
                LeagueDataCache.Standings(date: Date(), rows: rows, teams: teams),
                key: LeagueDataCache.standingsKey(league.id)
            )
        }
    }

    /// The device's one-ever free look at real data (see
    /// `LeagueDataCache.hasUsedFreeFill`) — explicit and centralized, not
    /// triggered lazily from any screen. Fills Matches + Standings for the
    /// **home league only** (Premier League), regardless of which/how many
    /// leagues are actually enabled — a multi-league subscriber's other
    /// leagues just need one ordinary gated tap (instant, no ad, since
    /// they're subscribed) the first time they're opened, same as any other
    /// never-before-seen league after this point. Call once, at launch.
    static func performFirstLaunchFreeFillIfNeeded() async {
        guard !LeagueDataCache.hasUsedFreeFill else { return }
        let league = Leagues.home
        async let matchesReq = pullLiveMatches(for: league)
        async let standingsReq = league.client.standings()
        async let teamsReq = cachedTeams(for: league)
        guard let rows = try? await standingsReq, let teams = try? await teamsReq else { return }
        _ = try? await matchesReq
        LeagueDataCache.save(
            LeagueDataCache.Standings(date: Date(), rows: rows, teams: teams),
            key: LeagueDataCache.standingsKey(league.id)
        )
        LeagueDataCache.consumeFreeFill()
    }

    // MARK: - Per-resource cache-first loaders

    /// Teams: functional/free. Served from cache within its TTL; otherwise fetched
    /// and re-cached. On a fetch failure with any cached copy, the stale copy is
    /// used rather than failing the whole load. The Worker's own `/teams` route
    /// has no live upstream path at all (seasonal — the nightly cron is the only
    /// way it ever changes server-side), so fetching it more often than this TTL
    /// never buys fresher data, only spends Cloudflare requests for nothing.
    private static func cachedTeams(for league: LeagueOption) async throws -> [TeamDTO] {
        let key = LeagueDataCache.teamsKey(league.id)
        switch LeagueDataCache.read(LeagueDataCache.Teams.self, key: key) {
        case .hit(let cached) where LeagueDataCache.isFresh(cached.date, ttl: CacheTTL.teams):
            return cached.items
        case .hit(let cached):
            return (try? await fetchTeams(league, key: key, fallback: cached.items)) ?? cached.items
        case .empty, .corrupt:
            return try await fetchTeams(league, key: key, fallback: [])
        }
    }

    // `fallback` covers a *successful but empty* response (e.g. the league is in
    // its close-season "blocked" window — see seasonPhase.ts — and the Worker is
    // correctly serving its current store as-is). That must never overwrite a
    // cache that already has real data; only a genuinely fresh/non-empty result
    // gets written. A network failure is handled separately, by the caller's `try?`.
    private static func fetchTeams(_ league: LeagueOption, key: String, fallback: [TeamDTO]) async throws -> [TeamDTO] {
        let teams = try await league.client.teams()
        if teams.isEmpty, !fallback.isEmpty { return fallback }
        LeagueDataCache.save(LeagueDataCache.Teams(date: Date(), items: teams), key: key)
        return teams
    }

    /// Matches (schedule + live state — gated): read from cache **only**,
    /// regardless of age. A round-flow open, or opening the Matches tab, is
    /// never itself a free fetch — the Fixtures-view courtesy prompt and the
    /// Matches tab's own refresh button are the only paths that actually call
    /// `pullLiveMatches`, and both go through the ad gate. The single
    /// exception (first-ever launch) is handled once, centrally, by
    /// `performFirstLaunchFreeFillIfNeeded` — never lazily here.
    private static func cachedMatches(for league: LeagueOption) -> (items: [MatchDTO], date: Date?) {
        guard let cached = LeagueDataCache.load(LeagueDataCache.Matches.self, key: LeagueDataCache.matchesKey(league.id)) else {
            return ([], nil)
        }
        return (cached.items, cached.date)
    }

    /// Standings (the table — gated): same cache-only policy as `cachedMatches`
    /// above, same single centralized exception.
    private static func cachedStandings(for league: LeagueOption) -> (rows: [StandingDTO], date: Date?) {
        guard case .hit(let cached) = LeagueDataCache.read(LeagueDataCache.Standings.self, key: LeagueDataCache.standingsKey(league.id)) else {
            return ([], nil)
        }
        return (cached.rows, cached.date)
    }
}
