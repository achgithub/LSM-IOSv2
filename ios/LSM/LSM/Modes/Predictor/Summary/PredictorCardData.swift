import Foundation

enum PredictorCardType: Equatable {
    case fixtures
    case entryClosed
    case weeklyResults
    case league
    case winner
}

extension PredictorCardType {
    var sectionLabel: String {
        switch self {
        case .fixtures:      return "FIXTURES"
        case .entryClosed:   return "ENTRIES CLOSED"
        case .weeklyResults: return "WEEKLY RESULTS"
        case .league:        return "LEAGUE TABLE"
        case .winner:        return "FINAL STANDINGS"
        }
    }
}

struct PredictorWeekResult: Identifiable {
    let id: UUID
    let position: Int
    let playerName: String
    let points: Int
}

struct PredictorStandingEntry: Identifiable {
    let id: UUID
    let position: Int
    let playerName: String
    let totalPoints: Int
    let thisRoundPoints: Int?
}

/// One slot on the winner podium. Multiple entries can share a position when
/// players are tied — they all receive the same medal colour.
struct PredictorPodiumEntry: Identifiable {
    let id: UUID
    let position: Int  // 1, 2, or 3
    let playerName: String
    let totalPoints: Int
}

/// Flattened, render-ready snapshot for a Predictor share card. A pure value
/// type with no SwiftData model references so it renders safely under ImageRenderer.
struct PredictorCardData {
    let type: PredictorCardType
    let gameName: String
    let appName: String
    let leagueName: String
    let matchdayNumber: Int
    let entrantCount: Int
    let timestampLabel: String
    let fixtures: [SummaryFixture]           // reuses the mode-agnostic LMS struct
    let weeklyResults: [PredictorWeekResult]
    let standings: [PredictorStandingEntry]
    let podium: [PredictorPodiumEntry]

    static func make(
        type: PredictorCardType,
        game: Game,
        round: Round,
        teamsById: [Int: TeamDTO],
        roundMatches: [MatchDTO]
    ) -> PredictorCardData {
        PredictorCardData(
            type: type,
            gameName: game.name,
            appName: "Predictor",
            leagueName: game.leagueLabel,
            matchdayNumber: round.roundNumber,
            entrantCount: game.players.count,
            timestampLabel: makeTimestamp(type: type, round: round),
            fixtures: makeFixtures(matches: roundMatches, teamsById: teamsById),
            weeklyResults: makeWeeklyResults(game: game, round: round),
            standings: makeStandings(game: game, latestRound: round),
            podium: makePodium(game: game)
        )
    }

    // MARK: - Builders

    private static func teamName(_ id: Int, _ teamsById: [Int: TeamDTO]) -> String {
        teamsById[id]?.shortName ?? teamsById[id]?.name ?? "Team \(id)"
    }

    private static func makeFixtures(matches: [MatchDTO], teamsById: [Int: TeamDTO]) -> [SummaryFixture] {
        matches
            .sorted(by: MatchDTO.byKickoffThenId)
            .map { match in
                SummaryFixture(
                    id: match.id,
                    homeName: teamName(match.homeTeamId, teamsById),
                    awayName: teamName(match.awayTeamId, teamsById),
                    kickoff: FixtureFormat.kickoffDate(match.kickoff)
                )
            }
    }

    private static func makeTimestamp(type: PredictorCardType, round: Round) -> String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE d MMM HH:mm")
        switch type {
        case .fixtures:
            return AppString("Deadline · \(formatter.string(from: round.deadline))")
        case .entryClosed:
            return AppString("Closed · \(formatter.string(from: round.deadline))")
        case .weeklyResults, .league, .winner:
            return AppString("Matchday \(round.roundNumber)")
        }
    }

    private static func makeWeeklyResults(game: Game, round: Round) -> [PredictorWeekResult] {
        let totals: [(Player, Int)] = game.players.map { player in
            let pts = round.predictions
                .filter { $0.player?.id == player.id }
                .compactMap(\.pointsAwarded)
                .reduce(0, +)
            return (player, pts)
        }
        let sorted = totals.sorted { a, b in
            a.1 != b.1 ? a.1 > b.1 : a.0.name.localizedCaseInsensitiveCompare(b.0.name) == .orderedAscending
        }
        var results: [PredictorWeekResult] = []
        var position = 0
        var lastPts: Int?
        for (index, entry) in sorted.enumerated() {
            if entry.1 != lastPts { position = index + 1; lastPts = entry.1 }
            results.append(PredictorWeekResult(id: entry.0.id, position: position,
                                               playerName: entry.0.name, points: entry.1))
        }
        return results
    }

    private static func makeStandings(game: Game, latestRound: Round) -> [PredictorStandingEntry] {
        PredictorStandings.rows(for: game).map { row in
            let thisRound: Int? = latestRound.status == .closed
                ? latestRound.predictions
                    .filter { $0.player?.id == row.player.id }
                    .compactMap(\.pointsAwarded)
                    .reduce(0, +)
                : nil
            return PredictorStandingEntry(
                id: row.player.id,
                position: row.position,
                playerName: row.player.name,
                totalPoints: row.points,
                thisRoundPoints: thisRound
            )
        }
    }

    private static func makePodium(game: Game) -> [PredictorPodiumEntry] {
        PredictorStandings.rows(for: game)
            .filter { $0.position <= 3 }
            .map { PredictorPodiumEntry(id: $0.player.id, position: $0.position,
                                        playerName: $0.player.name, totalPoints: $0.points) }
    }
}
