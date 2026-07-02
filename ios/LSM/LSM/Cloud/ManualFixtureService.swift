import Foundation

/// Manager-authored one-off fixtures for a single game — e.g. a local pub
/// team dropped into a round for a laugh, or a stand-in if the real fixture
/// provider is unavailable. Scores are always entered by hand (see
/// `ResultsEntryView`/`PredictorResultsEntryView`, both already manual-first).
///
/// Lives entirely in the same on-disk cache real fixtures use
/// (`LeagueDataCache`), under one synthetic league id derived from the game
/// itself (`Leagues.manualLeagueId`), so every round-flow screen — open
/// round, picks, results, cloud push — handles it exactly like a real league
/// with zero special-casing, the same trick the tutorial's seeded data uses.
///
/// Deliberately NOT reachable from New Game or Settings, and never counted
/// toward subscription league allowance (`Leagues.lookup` resolves it without
/// ever adding it to `Leagues.all`) — there's no way to set one up ahead of
/// time or reuse it across games, so it can never substitute for subscribing
/// to a real league.
enum ManualFixtureService {

    enum AddTeamError: LocalizedError {
        case duplicatesRealTeam(String)

        var errorDescription: String? {
            switch self {
            case .duplicatesRealTeam(let name):
                return AppString("\"\(name)\" is already a team in this game's league(s) — pick a different name.")
            }
        }
    }

    static func leagueId(for game: Game) -> String {
        Leagues.manualLeagueId(for: game.id)
    }

    // MARK: - Teams

    static func manualTeams(for game: Game) -> [TeamDTO] {
        LeagueDataCache.load(LeagueDataCache.Teams.self, key: LeagueDataCache.teamsKey(leagueId(for: game)))?.items ?? []
    }

    /// Finds an existing manual team by exact (case-insensitive, trimmed)
    /// name, or creates a new one. `realTeamNames` should be the names of
    /// every *real* (non-manual) team already loaded for this game's
    /// league(s) — checked once here, up front; see `reconcile` for the
    /// ongoing safety net if a real team is later added/renamed to match.
    static func team(named rawName: String, for game: Game, realTeamNames: Set<String>) -> Result<TeamDTO, AddTeamError> {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let existing = manualTeams(for: game)
        if let match = existing.first(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
            return .success(match)
        }
        if realTeamNames.contains(where: { $0.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
            return .failure(.duplicatesRealTeam(name))
        }
        let league = leagueId(for: game)
        let externalId = stableId(seed: "\(game.id.uuidString)|team|\(name.lowercased())")
        let team = TeamDTO(
            id: "manual-\(externalId)", externalId: externalId,
            name: name, shortName: String(name.prefix(12)), tla: nil,
            leagueId: league
        )
        LeagueDataCache.save(LeagueDataCache.Teams(date: Date(), items: existing + [team]), key: LeagueDataCache.teamsKey(league))
        return .success(team)
    }

    // MARK: - Fixtures

    static func manualMatches(for game: Game) -> [MatchDTO] {
        LeagueDataCache.load(LeagueDataCache.Matches.self, key: LeagueDataCache.matchesKey(leagueId(for: game)))?.items ?? []
    }

    /// Adds the fixture and, on a game's first ever manual fixture, folds the
    /// synthetic league into `game.leagueIdsRaw` so it blends into the normal
    /// round-opening flow alongside the game's real league(s) from now on.
    /// Callers still need `context.save()` afterwards (same convention as
    /// `GameLogicService` — mutation here, persistence at the call site).
    @discardableResult
    static func addFixture(homeTeam: TeamDTO, awayTeam: TeamDTO, kickoff: Date, for game: Game) -> MatchDTO {
        let league = leagueId(for: game)
        let existing = manualMatches(for: game)
        let id = stableId(seed: "\(game.id.uuidString)|match|\(homeTeam.externalId)|\(awayTeam.externalId)|\(existing.count)")
        let match = MatchDTO(
            id: id, matchday: nil,
            kickoff: ISO8601DateFormatter().string(from: kickoff),
            status: "SCHEDULED", minute: nil,
            homeTeamId: homeTeam.externalId, awayTeamId: awayTeam.externalId,
            homeScore: nil, awayScore: nil, winner: nil,
            leagueId: league
        )
        LeagueDataCache.save(LeagueDataCache.Matches(date: Date(), items: existing + [match]), key: LeagueDataCache.matchesKey(league))
        if !game.leagueIdsRaw.contains(league) { game.leagueIdsRaw.append(league) }
        return match
    }

    // MARK: - Reconciliation

    /// Removes any manual team (and fixtures referencing it) whose name now
    /// collides with a real team's name — e.g. the real fixture provider
    /// later adds or renames a team to match something a manager typed in by
    /// hand. Called from `LeagueData.load` on every load, so a stale manual
    /// entry can never coexist with its real twin for long. Returns true if
    /// anything was purged, so the caller can re-merge with clean data.
    @discardableResult
    static func reconcile(realTeamNames: Set<String>, leagueId: String) -> Bool {
        guard let teams = LeagueDataCache.load(LeagueDataCache.Teams.self, key: LeagueDataCache.teamsKey(leagueId)),
              !teams.items.isEmpty else { return false }

        let collidingIds = Set(teams.items.filter { team in
            realTeamNames.contains { $0.localizedCaseInsensitiveCompare(team.name) == .orderedSame }
        }.map(\.externalId))
        guard !collidingIds.isEmpty else { return false }

        let keptTeams = teams.items.filter { !collidingIds.contains($0.externalId) }
        LeagueDataCache.save(LeagueDataCache.Teams(date: teams.date, items: keptTeams), key: LeagueDataCache.teamsKey(leagueId))

        if let matches = LeagueDataCache.load(LeagueDataCache.Matches.self, key: LeagueDataCache.matchesKey(leagueId)) {
            let keptMatches = matches.items.filter { !collidingIds.contains($0.homeTeamId) && !collidingIds.contains($0.awayTeamId) }
            LeagueDataCache.save(LeagueDataCache.Matches(date: matches.date, items: keptMatches), key: LeagueDataCache.matchesKey(leagueId))
        }
        return true
    }

    // MARK: - Ids

    /// Deterministic id in a large negative range — clear of both real
    /// football-data ids (always positive) and the tutorial's synthetic ids
    /// (positive, 8000/9000-range), so the three can never collide.
    private static func stableId(seed: String) -> Int {
        var hasher = Hasher()
        hasher.combine(seed)
        return -(abs(hasher.finalize()) % 900_000_000) - 100_000_000
    }
}
