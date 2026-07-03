import Testing
import Foundation
@testable import LSM

/// Covers the shared fixture-visibility horizon (see fixture-horizon-logic
/// design memory): date-clustering (not matchday labels), the anchor-to-
/// first-fixture target/ceiling snap, and the real-world reschedule shapes
/// it's built to survive.
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

    @Test func outlierRearrangedWellBeyondTheAnchoredCeilingDoesNotDragOrBlockItsMatchday() {
        // MD2: four fixtures near the anchor (~12 days), one rearranged so
        // far out (60 days) that it's still beyond the ceiling even once the
        // ceiling is measured from the anchor (~12 + 35 = ~47), not from
        // today.
        var fixtures = (1...4).map { fixture($0, daysFromNow: 12 + Double($0) * 0.1) }
        fixtures.append(fixture(5, daysFromNow: 60))
        let eligible = FixtureHorizon.eligibleFixtureIds(fixtures: fixtures)
        #expect(eligible == Set(1...4))
    }

    @Test func fixtureBroughtForwardBecomesTheAnchorWithoutPullingInItsOldMatchday() {
        // One MD8 fixture is brought forward to 15 days — it becomes the
        // anchor. The rest of MD8 sits at 60 days, still beyond the anchored
        // ceiling (15 + 35 = 50), so it stays closed; only the brought-
        // forward fixture opens, on its own schedule.
        var fixtures = (1...4).map { fixture($0, daysFromNow: 60 + Double($0) * 0.1) } // rest of MD8
        fixtures.append(fixture(5, daysFromNow: 15)) // brought forward
        let eligible = FixtureHorizon.eligibleFixtureIds(fixtures: fixtures)
        #expect(eligible == Set([5]))
    }

    @Test func nextClusterWithinTheAnchoredCeilingIsIncludedWhole() {
        // Anchor is the near cluster (~day 3). Target = anchor+28 (~31),
        // ceiling = anchor+35 (~38). The next cluster sits at ~35 days —
        // past target, still within the anchored ceiling — so it's admitted
        // whole rather than cut.
        let near = (1...3).map { fixture($0, daysFromNow: 3 + Double($0) * 0.1) }
        let next = (4...6).map { fixture($0, daysFromNow: 35 + Double($0) * 0.1) }
        let eligible = FixtureHorizon.eligibleFixtureIds(fixtures: near + next)
        #expect(eligible == Set(1...6))
    }

    @Test func horizonAnchorsToTheFirstAvailableFixtureNotToday() {
        // Close season: the only cluster available is 40 days out (past a
        // now-anchored 35-day ceiling — e.g. next season doesn't kick off
        // for 6 weeks). It must still open: the window is measured from the
        // first available fixture, so the ceiling becomes 40+35=75, not
        // today+35. Regression test for a real bug — without an anchor tied
        // to the first fixture, close season zeroed out fixtures app-wide.
        let far = (1...3).map { fixture($0, daysFromNow: 40 + Double($0) * 0.1) }
        let eligible = FixtureHorizon.eligibleFixtureIds(fixtures: far)
        #expect(eligible == Set(1...3))
    }

    @Test func clusterBeyondTheAnchoredCeilingIsStillExcluded() {
        // Nearest cluster (the anchor) at 40 days; a further cluster at 80
        // days is beyond even the anchored ceiling (40+35=75), so it's
        // excluded — anchoring to the first fixture widens the window, it
        // doesn't remove the cap on how much *more* it can reach.
        let nearest = (1...2).map { fixture($0, daysFromNow: 40 + Double($0) * 0.1) }
        let further = (3...4).map { fixture($0, daysFromNow: 80 + Double($0) * 0.1) }
        let eligible = FixtureHorizon.eligibleFixtureIds(fixtures: nearest + further)
        #expect(eligible == Set(1...2))
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

    @Test func blendedLeaguesShareOneAnchorNotIndependentClocks() {
        // League A's nearest fixture (day 10) becomes the SHARED anchor for
        // the whole blend. League B's own nearest fixture is day 40 — beyond
        // a now-anchored ceiling, but within 35 days of the shared anchor
        // (10+35=45), so it still opens. Clustering stays per-league; only
        // the anchor is shared.
        let leagueA = (1...2).map { fixture($0, daysFromNow: 10, leagueId: "A") }
        let leagueB = (3...4).map { fixture($0, daysFromNow: 40, leagueId: "B") }
        let eligible = FixtureHorizon.eligibleFixtureIds(fixtures: leagueA + leagueB)
        #expect(eligible == Set(1...4))
    }

    @Test func gapWithNoGamesStretchesTheAnchoredCeilingToStillCaptureRealRounds() {
        // Anchor is day 5 (nearest fixture); target = 33, ceiling = 40.
        // Rounds at day 5 and day 12 fit within target. Then a blank
        // stretch with no fixtures at all, resuming at day 40 — past target
        // but exactly at the anchored ceiling, so it's still admitted: the
        // gap doesn't shrink the real number of rounds on offer, it just
        // uses more of the calendar allowance to reach them.
        var fixtures = (1...2).map { fixture($0, daysFromNow: 5, leagueId: league) }
        fixtures += (3...4).map { fixture($0, daysFromNow: 12, leagueId: league) }
        // (deliberately nothing between day 19 and day 33 — the gap)
        fixtures += (5...6).map { fixture($0, daysFromNow: 40, leagueId: league) }
        let eligible = FixtureHorizon.eligibleFixtureIds(fixtures: fixtures)
        #expect(eligible == Set(1...6))
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
