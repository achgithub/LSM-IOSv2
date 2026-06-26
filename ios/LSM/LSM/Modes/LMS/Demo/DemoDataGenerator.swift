import Foundation

/// Pure, deterministic sample data for the "Show Me" walkthrough — no persistence,
/// no SwiftData, no network. It produces the wire types (`TeamDTO`, `MatchDTO`,
/// `StandingDTO`) that the rest of the app reads through the normal league-data
/// cache, plus the scripted picks/results the walkthrough applies via the real
/// services. Everything here is fixed and offline so the demo plays out the same
/// way every time and works with no connection.
///
/// The script is engineered so a full game resolves in exactly two rounds to a
/// single winner, while showing off the result rules along the way:
///   Round 1 (4 players): a win, a win, a draw (eliminated), a postponed match
///                        (survives — the edge case) → 3 carry forward.
///   Round 2 (3 players): a win (survives) and two losses → 1 survivor, declared
///                        the winner.
enum DemoDataGenerator {

    // MARK: - Identifiers

    /// Demo ids are kept well clear of any real football-data id range so a demo
    /// can never collide with cached real data, even though it uses its own
    /// league cache anyway.
    static let firstTeamId = 9001
    static let firstMatchId = 8001

    // MARK: - Players

    /// The four sample players, in the order they're added. Plain first names so
    /// the demo reads naturally and isn't mistaken for real saved players.
    static let playerNames = ["Alex", "Sam", "Jordan", "Casey"]

    // MARK: - Teams

    /// 20 fictional clubs (matches the demo league's `teamsCount`). Invented names
    /// only — no real clubs — so there's no trademark or "is this live data?"
    /// confusion. Only the first 14 are used by the scripted fixtures; the rest
    /// round out the standings table.
    private static let teamNames: [(name: String, short: String, tla: String)] = [ // swiftlint:disable:this large_tuple
        ("Riverside Rovers", "Riverside", "RIV"),
        ("Hilltop Harriers", "Hilltop", "HIL"),
        ("Coastline City", "Coastline", "COA"),
        ("Meadow Town", "Meadow", "MEA"),
        ("Bridgeford United", "Bridgeford", "BRI"),
        ("Castleton Athletic", "Castleton", "CAS"),
        ("Parkside Albion", "Parkside", "PAR"),
        ("Lakeview Wanderers", "Lakeview", "LAK"),
        ("Oakfield FC", "Oakfield", "OAK"),
        ("Northgate Town", "Northgate", "NOR"),
        ("Sunvale City", "Sunvale", "SUN"),
        ("Westport United", "Westport", "WES"),
        ("Eastbrook Rovers", "Eastbrook", "EAS"),
        ("Granite Athletic", "Granite", "GRA"),
        ("Highmoor FC", "Highmoor", "HIG"),
        ("Stormont Town", "Stormont", "STO"),
        ("Cedar Park", "Cedar", "CED"),
        ("Valley United", "Valley", "VAL"),
        ("Kingsway City", "Kingsway", "KIN"),
        ("Marsh Athletic", "Marsh", "MAR")
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
            let position = offset + 1
            // Plausible, monotonically-decreasing table so anything that reads
            // standings (positions on cards, etc.) looks sensible.
            let won = max(0, 12 - offset / 2)
            let lost = min(offset, 12)
            let drawn = 3
            let played = won + lost + drawn
            return StandingDTO(
                teamId: teamId,
                position: position,
                played: played,
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

    // MARK: - Fixtures & scripted outcomes

    /// One scripted fixture: which teams, what result, and the pretty score shown
    /// on summary cards. `outcome` is what the walkthrough feeds through
    /// `GameLogicService.applyResult` — the score/winner/status only dress the
    /// `MatchDTO` so cards read correctly.
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

    /// Round 1 fixtures (matchday 1). Kickoffs are placed a few days back so the
    /// round reads as "just played".
    static let round1Fixtures: [ScriptedFixture] = [
        ScriptedFixture(matchId: firstMatchId, matchday: 1, homeTeamId: team(1), awayTeamId: team(2),
                        outcome: .homeWin, homeScore: 2, awayScore: 0),
        ScriptedFixture(matchId: firstMatchId + 1, matchday: 1, homeTeamId: team(3), awayTeamId: team(4),
                        outcome: .awayWin, homeScore: 0, awayScore: 1),
        ScriptedFixture(matchId: firstMatchId + 2, matchday: 1, homeTeamId: team(5), awayTeamId: team(6),
                        outcome: .draw, homeScore: 1, awayScore: 1),
        ScriptedFixture(matchId: firstMatchId + 3, matchday: 1, homeTeamId: team(7), awayTeamId: team(8),
                        outcome: .postponed, homeScore: nil, awayScore: nil)
    ]

    /// Round 2 fixtures (matchday 2).
    static let round2Fixtures: [ScriptedFixture] = [
        ScriptedFixture(matchId: firstMatchId + 4, matchday: 2, homeTeamId: team(9), awayTeamId: team(10),
                        outcome: .homeWin, homeScore: 2, awayScore: 1),
        ScriptedFixture(matchId: firstMatchId + 5, matchday: 2, homeTeamId: team(11), awayTeamId: team(12),
                        outcome: .homeWin, homeScore: 1, awayScore: 0),
        ScriptedFixture(matchId: firstMatchId + 6, matchday: 2, homeTeamId: team(13), awayTeamId: team(14),
                        outcome: .awayWin, homeScore: 0, awayScore: 2)
    ]

    /// Player name → the team id they pick in round 1. Chosen so:
    ///   Alex   → Riverside (win)      → survives
    ///   Sam    → Meadow (away win)    → survives  (and wins it all next round)
    ///   Jordan → Bridgeford (draw)    → eliminated (draw counts as a loss)
    ///   Casey  → Parkside (postponed) → survives  (the edge case)
    static let round1Picks: [String: Int] = [
        "Alex": team(1),
        "Sam": team(4),
        "Jordan": team(5),
        "Casey": team(7)
    ]

    /// Round 2 picks for the three survivors. Chosen so only Sam comes through:
    ///   Alex  → Northgate (lost at home match) → eliminated
    ///   Sam   → Sunvale (home win)             → survives → winner
    ///   Casey → Eastbrook (lost away match)    → eliminated
    static let round2Picks: [String: Int] = [
        "Alex": team(10),
        "Sam": team(11),
        "Casey": team(13)
    ]

    /// The name of the player who ends up the sole winner — so the final step can
    /// name them without re-deriving the result.
    static let winnerName = "Sam"

    // MARK: - MatchDTOs for the cache

    /// All scripted fixtures as `MatchDTO`s to seed into the matches cache, so
    /// every screen (Open Round, Picks, Results, summary cards) finds them
    /// locally. Round 1 is marked FINISHED with scores; the postponed game is
    /// POSTPONED; round 2 is FINISHED too (the whole game is pre-scripted).
    static func matches() -> [MatchDTO] {
        (round1Fixtures + round2Fixtures).map { f in
            let status = f.outcome == .postponed ? "POSTPONED" : "FINISHED"
            return MatchDTO(
                id: f.matchId,
                matchday: f.matchday,
                kickoff: isoString(daysFromNow: f.matchday == 1 ? -3 : -1),
                status: status,
                minute: nil,
                homeTeamId: f.homeTeamId,
                awayTeamId: f.awayTeamId,
                homeScore: f.homeScore,
                awayScore: f.awayScore,
                winner: winnerString(f.outcome),
                leagueId: Leagues.demoLeagueId
            )
        }
    }

    // MARK: - Helpers

    private static func winnerString(_ outcome: FixtureOutcome) -> String? {
        switch outcome {
        case .homeWin: return "HOME_TEAM"
        case .awayWin: return "AWAY_TEAM"
        case .draw: return "DRAW"
        case .postponed: return nil
        }
    }

    private static func isoString(daysFromNow days: Int) -> String {
        let date = Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? Date()
        return ISO8601DateFormatter().string(from: date)
    }
}
