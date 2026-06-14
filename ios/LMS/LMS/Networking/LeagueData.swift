import Foundation

/// A snapshot of the provider data the round-flow screens need, fetched together.
struct LeagueData {
    let fixtures: [FixtureDTO]
    let teamsById: [Int: TeamDTO]
    let standingsByTeam: [Int: StandingDTO]

    static func load() async throws -> LeagueData {
        async let fixturesReq = APIClient.shared.fixtures()
        async let teamsReq = APIClient.shared.teams()
        async let standingsReq = APIClient.shared.standings()
        let (fixtures, teams, standings) = try await (fixturesReq, teamsReq, standingsReq)
        return LeagueData(
            fixtures: fixtures,
            teamsById: Dictionary(teams.map { ($0.externalId, $0) }, uniquingKeysWith: { a, _ in a }),
            standingsByTeam: Dictionary(standings.map { ($0.teamId, $0) }, uniquingKeysWith: { a, _ in a })
        )
    }
}
