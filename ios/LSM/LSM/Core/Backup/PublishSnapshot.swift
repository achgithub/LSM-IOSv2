import Foundation

/// Complete, self-contained snapshot for one Predictor game's published page
/// (§0) — the manager-selected fixtures + scores for the recent window,
/// per-person weekly results, cumulative standings, and the next matchday's
/// selected fixtures. Predictor-only: LMS has no "predictions league" to
/// publish. The device is the source of truth (the manager chose the games
/// and fixtures), so this is built entirely from on-device data — the Pages
/// site can't assemble it from the Worker alone.
struct PublishSnapshot: Codable {
    let gameName: String
    let generatedAt: Date
    let recentRounds: [RoundSummary]
    let standings: [StandingRow]
    let nextFixtures: [FixtureSummary]

    struct FixtureSummary: Codable {
        let homeTeamName: String
        let awayTeamName: String
        let homeScore: Int?
        let awayScore: Int?
        let kickoff: String
    }

    struct PlayerWeekResult: Codable {
        let playerName: String
        let points: Int
    }

    struct RoundSummary: Codable {
        let roundNumber: Int
        let fixtures: [FixtureSummary]
        let results: [PlayerWeekResult]
    }

    struct StandingRow: Codable {
        let position: Int
        let playerName: String
        let points: Int
    }
}

enum PublishSnapshotBuilder {
    /// Default "recent window" per §0 — formalized later alongside the PWA's
    /// shared rolling-window constant; hardcoded here until that lands.
    static let recentWindow = 3

    static func build(for game: Game, data: LeagueData) -> PublishSnapshot {
        let closedRounds = game.rounds
            .filter { $0.status == .closed }
            .sorted { $0.roundNumber > $1.roundNumber }
            .prefix(recentWindow)
            .sorted { $0.roundNumber < $1.roundNumber }

        let recentRounds = closedRounds.map { round -> PublishSnapshot.RoundSummary in
            let fixtures = fixtureSummaries(for: round.fixtureIds, data: data)
            let pointsByPlayer = Dictionary(grouping: round.predictions, by: { $0.player?.id })
                .compactMapValues { predictions -> (Player, Int)? in
                    guard let player = predictions.first?.player else { return nil }
                    return (player, predictions.compactMap(\.pointsAwarded).reduce(0, +))
                }
            let results = pointsByPlayer.values
                .map { PublishSnapshot.PlayerWeekResult(playerName: $0.0.name, points: $0.1) }
                .sorted { $0.playerName.localizedCaseInsensitiveCompare($1.playerName) == .orderedAscending }
            return PublishSnapshot.RoundSummary(roundNumber: round.roundNumber, fixtures: fixtures, results: results)
        }

        let standings = PredictorStandings.rows(for: game).map {
            PublishSnapshot.StandingRow(position: $0.position, playerName: $0.player.name, points: $0.points)
        }

        let nextRound = game.rounds
            .filter { $0.status != .closed }
            .min { $0.roundNumber < $1.roundNumber }
        let nextFixtures = nextRound.map { fixtureSummaries(for: $0.fixtureIds, data: data) } ?? []

        return PublishSnapshot(
            gameName: game.name,
            generatedAt: Date(),
            recentRounds: recentRounds,
            standings: standings,
            nextFixtures: nextFixtures
        )
    }

    private static func fixtureSummaries(for fixtureIds: [Int], data: LeagueData) -> [PublishSnapshot.FixtureSummary] {
        let ids = Set(fixtureIds)
        return data.matches
            .filter { ids.contains($0.id) }
            .sorted(by: MatchDTO.byKickoffThenId)
            .map { fixture in
                PublishSnapshot.FixtureSummary(
                    homeTeamName: data.teamsById[fixture.homeTeamId]?.shortName
                        ?? data.teamsById[fixture.homeTeamId]?.name ?? "Team \(fixture.homeTeamId)",
                    awayTeamName: data.teamsById[fixture.awayTeamId]?.shortName
                        ?? data.teamsById[fixture.awayTeamId]?.name ?? "Team \(fixture.awayTeamId)",
                    homeScore: fixture.homeScore,
                    awayScore: fixture.awayScore,
                    kickoff: fixture.kickoff
                )
            }
    }
}
