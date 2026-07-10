import Testing
import Foundation
import SwiftData
@testable import LSM

/// Covers the manual-fixture concept (`ManualFixtureService` +
/// `GameLogicService.openRound`'s horizon bypass) — a manager typing in a
/// one-off fixture by hand. Deliberately mode-agnostic: every test below runs
/// against both an LMS and a Predictor `Game` to lock in that the mechanism
/// (synthetic per-game league, horizon bypass, scoring) never special-cases
/// LMS. See `ManualFixtureService`'s doc comment and
/// `Shared/Rounds/OpenRoundView.swift`.
struct ManualFixtureTests {

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Game.self, Player.self, Round.self, Pick.self, Prediction.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func game(mode: GameMode) -> Game {
        Game(name: "Test \(mode.rawValue) \(UUID())", season: "2025/26", allowRepeats: true, mode: mode)
    }

    // MARK: - Team creation / name collisions

    @Test(arguments: [GameMode.lms, GameMode.predictor])
    func teamCreationSucceedsAndIsIdempotentByName(mode: GameMode) {
        let g = game(mode: mode)
        let first = ManualFixtureService.team(named: "Dog & Duck FC", for: g, realTeamNames: [])
        let second = ManualFixtureService.team(named: "  dog & duck fc  ", for: g, realTeamNames: [])

        guard case .success(let a) = first, case .success(let b) = second else {
            Issue.record("expected both lookups to succeed")
            return
        }
        // Same (trimmed, case-insensitive) name must resolve to the same team,
        // not mint a duplicate — repeated adds during a session shouldn't fork ids.
        #expect(a.externalId == b.externalId)
        #expect(a.leagueId == ManualFixtureService.leagueId(for: g))
    }

    @Test(arguments: [GameMode.lms, GameMode.predictor])
    func teamNameCollidingWithRealTeamIsRejected(mode: GameMode) {
        let g = game(mode: mode)
        let result = ManualFixtureService.team(named: "Arsenal", for: g, realTeamNames: ["Arsenal"])
        guard case .failure(let error) = result else {
            Issue.record("expected a duplicatesRealTeam failure")
            return
        }
        if case .duplicatesRealTeam(let name) = error {
            #expect(name == "Arsenal")
        }
    }

    // MARK: - Fixture creation folds the synthetic league into the game

    @Test(arguments: [GameMode.lms, GameMode.predictor])
    func addingAManualFixtureFoldsTheSyntheticLeagueIntoTheGameOnlyOnce(mode: GameMode) {
        let g = game(mode: mode)
        let originalLeagueCount = g.leagueIdsRaw.count
        let home = TeamDTO(id: "manual-1", externalId: 1, name: "Home FC", shortName: nil, tla: nil, leagueId: ManualFixtureService.leagueId(for: g))
        let away = TeamDTO(id: "manual-2", externalId: 2, name: "Away FC", shortName: nil, tla: nil, leagueId: ManualFixtureService.leagueId(for: g))

        _ = ManualFixtureService.addFixture(homeTeam: home, awayTeam: away, kickoff: .now, for: g)
        #expect(g.leagueIdsRaw.count == originalLeagueCount + 1)

        // A second fixture must not fold the league in again.
        _ = ManualFixtureService.addFixture(homeTeam: home, awayTeam: away, kickoff: .now.addingTimeInterval(3600), for: g)
        #expect(g.leagueIdsRaw.count == originalLeagueCount + 1)

        // The game's resolved leagues (as OpenRoundView/PicksEntryView/etc.
        // see them) must include the manual league regardless of mode.
        #expect(g.leagues.map(\.id).contains(ManualFixtureService.leagueId(for: g)))
    }

    // MARK: - Reconciliation purges stale manual entries

    @Test func reconcilePurgesTeamAndMatchesThatNowCollideWithARealTeam() {
        let g = game(mode: .lms)
        let leagueId = ManualFixtureService.leagueId(for: g)
        // Go through `team(named:)` (not a hand-built TeamDTO) so the team is
        // actually persisted to the cache reconcile reads from.
        guard case .success(let home) = ManualFixtureService.team(named: "Sunday League FC", for: g, realTeamNames: []),
              case .success(let away) = ManualFixtureService.team(named: "Away FC", for: g, realTeamNames: []) else {
            Issue.record("expected team creation to succeed")
            return
        }
        _ = ManualFixtureService.addFixture(homeTeam: home, awayTeam: away, kickoff: .now, for: g)

        // A real team is later added/renamed to collide with the manual one.
        let purged = ManualFixtureService.reconcile(realTeamNames: ["Sunday League FC"], leagueId: leagueId)
        #expect(purged)

        let remainingTeams = ManualFixtureService.manualTeams(for: g)
        #expect(!remainingTeams.contains { $0.name == "Sunday League FC" })

        let remainingMatches = ManualFixtureService.manualMatches(for: g)
        #expect(remainingMatches.isEmpty) // the only match referenced the colliding team
    }

    @Test func reconcileIsANoOpWhenNothingCollides() {
        let g = game(mode: .lms)
        let leagueId = ManualFixtureService.leagueId(for: g)
        guard case .success(let home) = ManualFixtureService.team(named: "Sunday League FC", for: g, realTeamNames: []),
              case .success(let away) = ManualFixtureService.team(named: "Away FC", for: g, realTeamNames: []) else {
            Issue.record("expected team creation to succeed")
            return
        }
        _ = ManualFixtureService.addFixture(homeTeam: home, awayTeam: away, kickoff: .now, for: g)

        let purged = ManualFixtureService.reconcile(realTeamNames: ["Some Other Team"], leagueId: leagueId)
        #expect(!purged)
        #expect(ManualFixtureService.manualTeams(for: g).count == 2)
    }

    // MARK: - Horizon bypass at the actual enforcement point (openRound)

    /// `GameLogicService.openRound` is the real gate — `OpenRoundView`'s own
    /// filtering is UX only. A manual fixture must be admitted into a round
    /// even when it falls outside `FixtureHorizon`'s eligible window, and this
    /// must hold in a Predictor game exactly as it does in LMS.
    @Test(arguments: [GameMode.lms, GameMode.predictor])
    func manualFixtureBypassesTheHorizonGateOnOpenRound(mode: GameMode) throws {
        let context = try makeContext()
        let g = game(mode: mode)
        context.insert(g)

        let manualLeagueId = ManualFixtureService.leagueId(for: g)
        // Far outside any real horizon window (200 days out) — the manager
        // deliberately chose this kick-off, so it must be admitted regardless.
        let manualKickoff = ISO8601DateFormatter().string(from: .now.addingTimeInterval(200 * 86400))
        let manualFixture = MatchDTO(
            id: 999, matchday: nil, kickoff: manualKickoff, status: "SCHEDULED",
            minute: nil, homeTeamId: 1, awayTeamId: 2, homeScore: nil, awayScore: nil, winner: nil,
            leagueId: manualLeagueId
        )
        // A real anchor fixture 10 days out (establishes the horizon window)…
        let anchorKickoff = ISO8601DateFormatter().string(from: .now.addingTimeInterval(10 * 86400))
        let anchorFixture = MatchDTO(
            id: 1000, matchday: nil, kickoff: anchorKickoff, status: "SCHEDULED",
            minute: nil, homeTeamId: 3, awayTeamId: 4, homeScore: nil, awayScore: nil, winner: nil,
            leagueId: "REAL"
        )
        // …plus a real outlier well beyond that window's ceiling (10+35=45) —
        // this one, unlike the manual fixture, must NOT be admitted.
        let outlierKickoff = ISO8601DateFormatter().string(from: .now.addingTimeInterval(90 * 86400))
        let outlierFixture = MatchDTO(
            id: 1001, matchday: nil, kickoff: outlierKickoff, status: "SCHEDULED",
            minute: nil, homeTeamId: 5, awayTeamId: 6, homeScore: nil, awayScore: nil, winner: nil,
            leagueId: "REAL"
        )

        let round = GameLogicService.openRound(
            in: g,
            fixtureIds: [999, 1000, 1001],
            fixtures: [manualFixture, anchorFixture, outlierFixture],
            deadline: .now,
            context: context
        )

        #expect(round.fixtureIds.contains(999))
        #expect(round.fixtureIds.contains(1000))
        #expect(!round.fixtureIds.contains(1001))
    }

    // MARK: - Predictor scoring treats a manual fixture identically to a real one

    @Test func predictorScoresAManualFixtureExactlyLikeARealOne() throws {
        let context = try makeContext()
        let g = game(mode: .predictor)
        context.insert(g)
        // fixtureId here stands in for a manual fixture's negative stableId —
        // scoring has no dependency on fixture provenance, only on the id.
        let round = Round(roundNumber: 1, deadline: .now, fixtureIds: [-123_456], game: g)
        context.insert(round)
        let player = Player(name: "Alice", game: g)
        context.insert(player)
        let prediction = Prediction(fixtureId: -123_456, predictedHome: 2, predictedAway: 1, isJoker: false, player: player, round: round)
        context.insert(prediction)
        round.predictions = [prediction]

        try PredictorScoringService.closeRound(
            round, game: g, finalScores: [-123_456: (home: 2, away: 1)], context: context
        )

        #expect(round.status == .closed)
        #expect(prediction.pointsAwarded == g.predictorExactPoints)
    }
}
