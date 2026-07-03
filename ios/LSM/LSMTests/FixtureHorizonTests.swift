import Testing
import Foundation
@testable import LSM

/// Covers the shared fixture-visibility horizon (see fixture-horizon-logic
/// design memory): date-clustering (not matchday labels), the target/ceiling
/// snap, and the two real-world reschedule shapes it's built to survive.
struct FixtureHorizonTests {

    private let league = "TEST"

    private func fixture(_ id: Int, daysFromNow: Double, leagueId: String? = nil) -> MatchDTO {
        let kickoff = Date.now.addingTimeInterval(daysFromNow * 86400)
        let formatter = ISO8601DateFormatter()
        return MatchDTO(
            id: id, matchday: nil, kickoff: formatter.string(from: kickoff), status: "SCHEDULED",
            minute: nil, homeTeamId: 1, awayTeamId: 2, homeScore: nil, awayScore: nil, winner: nil,
            leagueId: leagueId ?? league
        )
    }

    private func undatedFixture(_ id: Int) -> MatchDTO {
        MatchDTO(
            id: id, matchday: nil, kickoff: "", status: "SCHEDULED",
            minute: nil, homeTeamId: 1, awayTeamId: 2, homeScore: nil, awayScore: nil, winner: nil,
            leagueId: league
        )
    }

    @Test func admitsWholeNearMatchdayWithinTarget() {
        // A normal weekend round, 10 days out — comfortably inside target.
        let md = (1...5).map { fixture($0, daysFromNow: 10 + Double($0) * 0.1) }
        let eligible = FixtureHorizon.eligibleFixtureIds(fixtures: md)
        #expect(eligible == Set(1...5))
    }

    @Test func outlierPushedSixWeeksOutDoesNotDragOrBlockItsMatchday() {
        // MD2: four fixtures at ~12 days, one rearranged 6 weeks (42 days) out.
        var fixtures = (1...4).map { fixture($0, daysFromNow: 12 + Double($0) * 0.1) }
        fixtures.append(fixture(5, daysFromNow: 42))
        let eligible = FixtureHorizon.eligibleFixtureIds(fixtures: fixtures)
        // The near cluster opens now; the outlier does not (it's 42 days out —
        // beyond even the 35-day ceiling).
        #expect(eligible == Set(1...4))
    }

    @Test func fixtureBroughtForwardJoinsWhicheverClusterItsNewDateFallsInto() {
        // MD8's real cluster sits ~40 days out (beyond the horizon), but one
        // of its fixtures was brought forward to 15 days — it should open
        // with whatever's near, on its own schedule, independent of the
        // label "MD8".
        var fixtures = (1...4).map { fixture($0, daysFromNow: 40 + Double($0) * 0.1) } // rest of MD8
        fixtures.append(fixture(5, daysFromNow: 15)) // brought forward
        let eligible = FixtureHorizon.eligibleFixtureIds(fixtures: fixtures)
        #expect(eligible == Set([5]))
    }

    @Test func nextClusterWithinCeilingIsIncludedWhole() {
        // First cluster ends at 20 days (within target). Second cluster ends
        // at 30 days — past the 28-day target, but still within the 35-day
        // ceiling, so it's admitted whole rather than cut.
        let near = (1...3).map { fixture($0, daysFromNow: 18 + Double($0) * 0.1) }
        let next = (4...6).map { fixture($0, daysFromNow: 30 + Double($0) * 0.1) }
        let eligible = FixtureHorizon.eligibleFixtureIds(fixtures: near + next)
        #expect(eligible == Set(1...6))
    }

    @Test func clusterBeyondCeilingIsCutEvenIfShortOfTarget() {
        // Only cluster available ends at 40 days — past the 35-day ceiling.
        // Nothing opens rather than including it, even though that leaves
        // the window at 0 days (there's simply nothing eligible yet).
        let far = (1...3).map { fixture($0, daysFromNow: 40 + Double($0) * 0.1) }
        let eligible = FixtureHorizon.eligibleFixtureIds(fixtures: far)
        #expect(eligible.isEmpty)
    }

    @Test func undatedFixturesAreExcludedNotDefaulted() {
        // Bundesliga-style stepwise confirmation: some far-out matchdays have
        // no kickoff at all yet. Must be skipped, not crash or fake a date.
        let dated = (1...3).map { fixture($0, daysFromNow: 10 + Double($0) * 0.1) }
        let undated = (4...6).map { undatedFixture($0) }
        let eligible = FixtureHorizon.eligibleFixtureIds(fixtures: dated + undated)
        #expect(eligible == Set(1...3))
    }

    @Test func softFloorAllowsAShorterWindowWhenDataDoesntExtendThatFar() {
        // Only 10 days of real fixtures exist (well under the 21-day floor) —
        // still fine to open everything that IS dated rather than blocking.
        let onlyNear = (1...3).map { fixture($0, daysFromNow: 8 + Double($0) * 0.1) }
        let eligible = FixtureHorizon.eligibleFixtureIds(fixtures: onlyNear)
        #expect(eligible == Set(1...3))
    }

    @Test func multipleLeaguesAreClusteredIndependently() {
        // League A has a near matchday; league B's nearest is far out. Each
        // league's own horizon should apply independently.
        let leagueA = (1...2).map { fixture($0, daysFromNow: 10, leagueId: "A") }
        let leagueB = (3...4).map { fixture($0, daysFromNow: 40, leagueId: "B") }
        let eligible = FixtureHorizon.eligibleFixtureIds(fixtures: leagueA + leagueB)
        #expect(eligible == Set(1...2))
    }

    @Test func gapWithNoGamesStretchesCalendarReachToStillCaptureTargetRoundsOfGames() {
        // Weekly rounds at day 7 and 14, then a 2-week gap with no fixtures
        // at all (nothing at day 21), resuming at day 35. The walk only ever
        // sees real cluster dates, so the blank fortnight isn't charged
        // against the 28-day target — it just means reaching 3 real rounds
        // of games takes 5 calendar weeks instead of 3.
        var fixtures = (1...2).map { fixture($0, daysFromNow: 7, leagueId: league) } // day 7
        fixtures += (3...4).map { fixture($0, daysFromNow: 14, leagueId: league) }   // day 14
        // (deliberately nothing around day 21/28 — the gap)
        fixtures += (5...6).map { fixture($0, daysFromNow: 35, leagueId: league) }   // day 35, right at the ceiling
        let eligible = FixtureHorizon.eligibleFixtureIds(fixtures: fixtures)
        #expect(eligible == Set(1...6)) // all 3 real rounds admitted, gap absorbed for free
    }

    @Test func horizonEndReportsTheFurthestAdmittedKickoff() {
        let md = (1...3).map { fixture($0, daysFromNow: 10 + Double($0)) }
        let end = FixtureHorizon.horizonEnd(leagueId: league, fixtures: md)
        #expect(end != nil)
        // Should equal the latest admitted fixture's kickoff (fixture 3, ~13 days out).
        let expected = Date.now.addingTimeInterval((10 + 3) * 86400)
        #expect(abs((end ?? .distantPast).timeIntervalSince(expected)) < 60)
    }
}
