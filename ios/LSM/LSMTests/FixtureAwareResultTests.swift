import Testing
import Foundation
import SwiftData
@testable import LSM

/// A team can play twice in one round (rearranged fixtures). `Pick.fixtureId`
/// disambiguates which occurrence a pick backs, so `applyResult` doesn't let a
/// win in one fixture and a loss in the other overwrite each other.
struct FixtureAwareResultTests {

    private func makeRound() throws -> (ModelContext, Round) {
        let container = try ModelContainer(
            for: Game.self, Player.self, Round.self, Pick.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let game = Game(name: "T", season: "2025/26", allowRepeats: false)
        context.insert(game)
        let round = Round(roundNumber: 1, deadline: .now, fixtureIds: [100, 200], game: game)
        context.insert(round)
        game.rounds.append(round)
        return (context, round)
    }

    @Test func pickResolvesToItsOwnFixtureWhenTeamPlaysTwice() throws {
        let (context, round) = try makeRound()
        let game = round.game!
        let player = Player(name: "A", game: game, entryNumber: 1)
        context.insert(player)
        game.players.append(player)

        // Arsenal (57) plays in fixture 100 (vs Chelsea) and fixture 200 (vs Everton).
        let pick = Pick(teamId: 57, fixtureId: 100, player: player, round: round)
        context.insert(pick)

        // Arsenal win fixture 100, then lose fixture 200 — result must stick to 100.
        GameLogicService.applyResult(fixtureId: 100, homeTeamId: 57, awayTeamId: 61, outcome: .homeWin, round: round)
        GameLogicService.applyResult(fixtureId: 200, homeTeamId: 57, awayTeamId: 62, outcome: .awayWin, round: round)

        #expect(pick.result == .win)
    }

    @Test func sameScenarioReversedOrderStillResolvesCorrectly() throws {
        let (context, round) = try makeRound()
        let game = round.game!
        let player = Player(name: "A", game: game, entryNumber: 1)
        context.insert(player)
        game.players.append(player)

        let pick = Pick(teamId: 57, fixtureId: 200, player: player, round: round)
        context.insert(pick)

        // This time the pick backs fixture 200, and fixture 100 is applied first.
        GameLogicService.applyResult(fixtureId: 100, homeTeamId: 57, awayTeamId: 61, outcome: .homeWin, round: round)
        GameLogicService.applyResult(fixtureId: 200, homeTeamId: 57, awayTeamId: 62, outcome: .awayWin, round: round)

        #expect(pick.result == .loss)
    }

    @Test func legacyNilFixtureIdPickFallsBackToMatchingAnyFixture() throws {
        let (context, round) = try makeRound()
        let game = round.game!
        let player = Player(name: "A", game: game, entryNumber: 1)
        context.insert(player)
        game.players.append(player)

        // A pick made before fixtureId existed — degrades to the old (last-write-wins) behavior.
        let pick = Pick(teamId: 57, player: player, round: round)
        context.insert(pick)

        GameLogicService.applyResult(fixtureId: 100, homeTeamId: 57, awayTeamId: 61, outcome: .homeWin, round: round)
        #expect(pick.result == .win)

        GameLogicService.applyResult(fixtureId: 200, homeTeamId: 57, awayTeamId: 62, outcome: .awayWin, round: round)
        #expect(pick.result == .loss)
    }
}
