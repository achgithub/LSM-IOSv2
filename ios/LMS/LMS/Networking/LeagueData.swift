import Foundation

/// A snapshot of the provider data the round-flow screens need, fetched together.
struct LeagueData {
    let fixtures: [FixtureDTO]
    let teamsById: [Int: TeamDTO]
    let standingsByTeam: [Int: StandingDTO]

    /// Load from the home league's Worker (the app default).
    static func load() async throws -> LeagueData {
        try await load(from: APIClient.shared)
    }

    /// Load from a specific league's Worker — used by round-scoped screens so a
    /// round always resolves against the league its fixtures came from.
    static func load(for league: LeagueOption) async throws -> LeagueData {
        try await load(from: league.client)
    }

    private static func load(from client: APIClient) async throws -> LeagueData {
        async let fixturesReq = client.fixtures()
        async let teamsReq = client.teams()
        async let standingsReq = client.standings()
        let (fixtures, teams, standings) = try await (fixturesReq, teamsReq, standingsReq)
        return LeagueData(
            fixtures: fixtures,
            teamsById: Dictionary(teams.map { ($0.externalId, $0) }, uniquingKeysWith: { a, _ in a }),
            standingsByTeam: Dictionary(standings.map { ($0.teamId, $0) }, uniquingKeysWith: { a, _ in a })
        )
    }
}
