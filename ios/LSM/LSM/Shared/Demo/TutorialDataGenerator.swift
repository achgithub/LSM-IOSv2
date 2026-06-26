import Foundation

/// Pure, deterministic sample data for the "See How It Works" tutorial — no
/// persistence, no SwiftData, no network. Produces TeamDTO/MatchDTO/StandingDTO
/// wire types seeded into the on-disk league cache so every screen finds them
/// locally with no connection. All data is fixed so the tutorial plays out
/// identically every time.
///
/// LMS script (2 rounds → Sam wins):
///   Round 1: home-win / away-win / draw (eliminated) / postponed (survives)
///   Round 2: one survivor wins, two eliminated
///
/// Predictor script (1 matchday, 4 fixtures):
///   User enters one prediction for Highmoor FC vs Stormont Town (pre-filled 2–0,
///   actual result 2–1). Other predictions and all results are scripted.
///   Sam wins the matchday.
enum TutorialDataGenerator {

    // MARK: - Identifiers

    /// IDs kept well clear of any real football-data range.
    static let firstTeamId = 9001
    static let lmsFirstMatchId = 8001
    static let predictorFirstMatchId = 8008

    // MARK: - Players

    static let playerNames = ["Alex", "Sam", "Jordan", "Casey"]

    // MARK: - Teams (20 fictional clubs)

    private static let teamNames: [(name: String, short: String, tla: String)] = [
        ("Riverside Rovers",   "Riverside",  "RIV"),
        ("Hilltop Harriers",   "Hilltop",    "HIL"),
        ("Coastline City",     "Coastline",  "COA"),
        ("Meadow Town",        "Meadow",     "MEA"),
        ("Bridgeford United",  "Bridgeford", "BRI"),
        ("Castleton Athletic", "Castleton",  "CAS"),
        ("Parkside Albion",    "Parkside",   "PAR"),
        ("Lakeview Wanderers", "Lakeview",   "LAK"),
        ("Oakfield FC",        "Oakfield",   "OAK"),
        ("Northgate Town",     "Northgate",  "NOR"),
        ("Sunvale City",       "Sunvale",    "SUN"),
        ("Westport United",    "Westport",   "WES"),
        ("Eastbrook Rovers",   "Eastbrook",  "EAS"),
        ("Granite Athletic",   "Granite",    "GRA"),
        ("Highmoor FC",        "Highmoor",   "HIG"),
        ("Stormont Town",      "Stormont",   "STO"),
        ("Cedar Park",         "Cedar",      "CED"),
        ("Valley United",      "Valley",     "VAL"),
        ("Kingsway City",      "Kingsway",   "KIN"),
        ("Marsh Athletic",     "Marsh",      "MAR")
    ]

    static func teams() -> [TeamDTO] {
        teamNames.enumerated().map { offset, t in
            let externalId = firstTeamId + offset
            return TeamDTO(
                id: "demo-\(externalId)",
                externalId: externalId,
                name: t.name,
                shortName: t.short,
                tla: t.tla,
                leagueId: Leagues.demoLeagueId
            )
        }
    }

    static func standings() -> [StandingDTO] {
        let updatedAt = isoString(daysFromNow: 0)
        return teamNames.indices.map { offset in
            let teamId = firstTeamId + offset
            let won = max(0, 12 - offset / 2)
            let lost = min(offset, 12)
            let drawn = 3
            return StandingDTO(
                teamId: teamId,
                position: offset + 1,
                played: won + lost + drawn,
                won: won,
                drawn: drawn,
                lost: lost,
                goalsFor: 40 - offset,
                goalsAgainst: 15 + offset,
                goalDifference: (40 - offset) - (15 + offset),
                points: won * 3 + drawn,
                updatedAt: updatedAt
            )
        }
    }

    // MARK: - Fixture type

    struct ScriptedFixture {
        let matchId: Int
        let matchday: Int
        let homeTeamId: Int
        let awayTeamId: Int
        let outcome: FixtureOutcome
        let homeScore: Int?
        let awayScore: Int?
    }

    private static func team(_ index1Based: Int) -> Int { firstTeamId + index1Based - 1 }

    // MARK: - LMS fixtures

    static let lmsRound1Fixtures: [ScriptedFixture] = [
        ScriptedFixture(matchId: lmsFirstMatchId,     matchday: 1, homeTeamId: team(1), awayTeamId: team(2),
                        outcome: .homeWin,   homeScore: 2,    awayScore: 0),
        ScriptedFixture(matchId: lmsFirstMatchId + 1, matchday: 1, homeTeamId: team(3), awayTeamId: team(4),
                        outcome: .awayWin,   homeScore: 0,    awayScore: 1),
        ScriptedFixture(matchId: lmsFirstMatchId + 2, matchday: 1, homeTeamId: team(5), awayTeamId: team(6),
                        outcome: .draw,      homeScore: 1,    awayScore: 1),
        ScriptedFixture(matchId: lmsFirstMatchId + 3, matchday: 1, homeTeamId: team(7), awayTeamId: team(8),
                        outcome: .postponed, homeScore: nil,  awayScore: nil)
    ]

    static let lmsRound2Fixtures: [ScriptedFixture] = [
        ScriptedFixture(matchId: lmsFirstMatchId + 4, matchday: 2, homeTeamId: team(9),  awayTeamId: team(10),
                        outcome: .homeWin, homeScore: 2, awayScore: 1),
        ScriptedFixture(matchId: lmsFirstMatchId + 5, matchday: 2, homeTeamId: team(11), awayTeamId: team(12),
                        outcome: .homeWin, homeScore: 1, awayScore: 0),
        ScriptedFixture(matchId: lmsFirstMatchId + 6, matchday: 2, homeTeamId: team(13), awayTeamId: team(14),
                        outcome: .awayWin, homeScore: 0, awayScore: 2)
    ]

    /// Round 1: Alex→Riverside(win✅) Sam→Meadow(away-win✅) Jordan→Bridgeford(draw❌) Casey→Parkside(postponed✅)
    static let lmsRound1Picks: [String: Int] = [
        "Alex":   team(1),
        "Sam":    team(4),
        "Jordan": team(5),
        "Casey":  team(7)
    ]

    /// Round 2: Alex→Northgate(loss❌) Sam→Sunvale(win✅ WINNER) Casey→Eastbrook(loss❌)
    static let lmsRound2Picks: [String: Int] = [
        "Alex":  team(10),
        "Sam":   team(11),
        "Casey": team(13)
    ]

    static let lmsWinnerName = "Sam"

    // MARK: - Predictor fixtures (matchday 3 — separate from LMS rounds)

    /// Fixture 8008 (Highmoor vs Stormont, actual 2–1) is the one the user predicts.
    /// Pre-filled hint is 2–0 — correct result but wrong GD (2 pts). If they type 2–1 exactly: 4 pts.
    static let predictorFixtures: [ScriptedFixture] = [
        ScriptedFixture(matchId: predictorFirstMatchId,     matchday: 3, homeTeamId: team(15), awayTeamId: team(16),
                        outcome: .homeWin, homeScore: 2, awayScore: 1),
        ScriptedFixture(matchId: predictorFirstMatchId + 1, matchday: 3, homeTeamId: team(17), awayTeamId: team(18),
                        outcome: .draw,    homeScore: 0, awayScore: 0),
        ScriptedFixture(matchId: predictorFirstMatchId + 2, matchday: 3, homeTeamId: team(19), awayTeamId: team(20),
                        outcome: .homeWin, homeScore: 3, awayScore: 1),
        ScriptedFixture(matchId: predictorFirstMatchId + 3, matchday: 3, homeTeamId: team(1),  awayTeamId: team(3),
                        outcome: .homeWin, homeScore: 1, awayScore: 0)
    ]

    /// Scripted predictions per player. Alex's prediction for fixture 8008 is overridden
    /// by what the user enters. Final scores (exact=4, GD=3, result=2, wrong=0):
    ///   Sam: 2+4+4+2 = 12 pts (wins)
    ///   Alex: 2+0+2+4 = 8 pts (or 10 if user enters exact 2-1)
    ///   Casey: 2+0+2+2 = 6 pts
    ///   Jordan: 0+2+2+0 = 4 pts
    static let predictorScriptedPredictions: [String: [Int: (home: Int, away: Int)]] = [
        "Alex": [
            predictorFirstMatchId:     (2, 0),  // overridden by user input
            predictorFirstMatchId + 1: (1, 0),  // wrong result (actual 0-0) = 0 pts
            predictorFirstMatchId + 2: (2, 1),  // correct result, wrong GD = 2 pts
            predictorFirstMatchId + 3: (1, 0)   // exact = 4 pts
        ],
        "Sam": [
            predictorFirstMatchId:     (1, 0),  // correct result, wrong GD = 2 pts
            predictorFirstMatchId + 1: (0, 0),  // exact = 4 pts
            predictorFirstMatchId + 2: (3, 1),  // exact = 4 pts
            predictorFirstMatchId + 3: (2, 0)   // correct result, wrong GD = 2 pts
        ],
        "Jordan": [
            predictorFirstMatchId:     (0, 1),  // wrong result = 0 pts
            predictorFirstMatchId + 1: (1, 1),  // same result (draw) = 2 pts
            predictorFirstMatchId + 2: (1, 0),  // correct result, wrong GD = 2 pts
            predictorFirstMatchId + 3: (0, 0)   // wrong result = 0 pts
        ],
        "Casey": [
            predictorFirstMatchId:     (3, 0),  // correct result, wrong GD = 2 pts
            predictorFirstMatchId + 1: (1, 0),  // wrong result = 0 pts
            predictorFirstMatchId + 2: (4, 1),  // correct result, wrong GD = 2 pts
            predictorFirstMatchId + 3: (2, 1)   // correct result, wrong GD = 2 pts
        ]
    ]

    /// Home/away team names for the fixture the user predicts — shown in the prediction input card.
    static var predictorUserFixture: (home: String, away: String) {
        (teamNames[14].name, teamNames[15].name) // team(15) = Highmoor FC, team(16) = Stormont Town
    }

    // MARK: - MatchDTOs for the league cache

    static func matches() -> [MatchDTO] {
        let lms = (lmsRound1Fixtures + lmsRound2Fixtures).map { f -> MatchDTO in
            MatchDTO(
                id: f.matchId,
                matchday: f.matchday,
                kickoff: isoString(daysFromNow: f.matchday == 1 ? -3 : -1),
                status: f.outcome == .postponed ? "POSTPONED" : "FINISHED",
                minute: nil,
                homeTeamId: f.homeTeamId,
                awayTeamId: f.awayTeamId,
                homeScore: f.homeScore,
                awayScore: f.awayScore,
                winner: winnerString(f.outcome),
                leagueId: Leagues.demoLeagueId
            )
        }
        let predictor = predictorFixtures.map { f -> MatchDTO in
            MatchDTO(
                id: f.matchId,
                matchday: f.matchday,
                kickoff: isoString(daysFromNow: -2),
                status: "FINISHED",
                minute: nil,
                homeTeamId: f.homeTeamId,
                awayTeamId: f.awayTeamId,
                homeScore: f.homeScore,
                awayScore: f.awayScore,
                winner: winnerString(f.outcome),
                leagueId: Leagues.demoLeagueId
            )
        }
        return lms + predictor
    }

    // MARK: - Helpers

    private static func winnerString(_ outcome: FixtureOutcome) -> String? {
        switch outcome {
        case .homeWin:   return "HOME_TEAM"
        case .awayWin:   return "AWAY_TEAM"
        case .draw:      return "DRAW"
        case .postponed: return nil
        }
    }

    static func isoString(daysFromNow days: Int) -> String {
        let date = Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? Date()
        return ISO8601DateFormatter().string(from: date)
    }
}
