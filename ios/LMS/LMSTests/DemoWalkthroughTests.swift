import Testing
import Foundation
import SwiftData
@testable import LMS

/// Tests for the "Show Me" demo. These drive `DemoDataService` through the same
/// services real games use and assert the scripted game resolves correctly, plus
/// that demo data is marked and cleared without touching real games.
@MainActor
struct DemoWalkthroughTests {

    /// Fresh in-memory store for each test.
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Game.self, Player.self, Round.self, Pick.self, RosterMember.self, PlayerGroup.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    /// Run the full scripted walkthrough (every advance step) on a context.
    @discardableResult
    private func runFullDemo(_ context: ModelContext) -> Game {
        let game = DemoDataService.createEmptyGame(context: context)
        DemoDataService.addPlayers(to: game, context: context)
        let r1 = DemoDataService.openRound1(in: game, context: context)
        DemoDataService.assignRound1Picks(game: game, round: r1, context: context)
        DemoDataService.closeRound1(game: game, round: r1, context: context)
        let r2 = DemoDataService.openRound2(in: game, context: context)
        DemoDataService.assignRound2Picks(game: game, round: r2, context: context)
        DemoDataService.closeRound2AndDeclareWinner(game: game, round: r2, context: context)
        return game
    }

    // MARK: - Game creation & marking

    @Test func emptyGameStartsMarkedAndPlayerless() throws {
        let context = try makeContext()
        let game = DemoDataService.createEmptyGame(context: context)
        #expect(game.isDemoData)
        #expect(game.players.isEmpty)
        #expect(game.rounds.isEmpty)
        #expect(game.status == .setup)
        // The demo game uses the local demo league, never the home league.
        #expect(game.leagueIdsRaw == [Leagues.demoLeagueId])
        #expect(game.leagues.map(\.id) == [Leagues.demoLeagueId])
    }

    @Test func addsFourSamplePlayers() throws {
        let context = try makeContext()
        let game = DemoDataService.createEmptyGame(context: context)
        DemoDataService.addPlayers(to: game, context: context)
        #expect(game.players.count == 4)
        #expect(Set(game.players.map(\.name)) == Set(DemoDataGenerator.playerNames))
        // Entry numbers are unique and sequential.
        #expect(Set(game.players.map(\.entryNumber)).count == 4)
    }

    // MARK: - Round 1: the postponed edge case

    @Test func roundOneLeavesThreeSurvivorsIncludingThePostponedPick() throws {
        let context = try makeContext()
        let game = DemoDataService.createEmptyGame(context: context)
        DemoDataService.addPlayers(to: game, context: context)
        let r1 = DemoDataService.openRound1(in: game, context: context)
        DemoDataService.assignRound1Picks(game: game, round: r1, context: context)
        DemoDataService.closeRound1(game: game, round: r1, context: context)

        // Three carry forward; the draw (Jordan) is the only one eliminated.
        #expect(game.activePlayers.count == 3)
        let active = Set(game.activePlayers.map(\.name))
        #expect(active == ["Alex", "Sam", "Casey"])
        #expect(player(named: "Jordan", in: game)?.status == .eliminated)
        // Edge case: the postponed pick (Casey) survives by default rules.
        #expect(player(named: "Casey", in: game)?.status == .active)
        #expect(r1.status == .closed)
    }

    // MARK: - Full game: exactly one winner in two rounds

    @Test func fullDemoProducesExactlyOneWinnerAndCompletes() throws {
        let context = try makeContext()
        let game = runFullDemo(context)

        #expect(game.status == .complete)
        #expect(game.lastOutcome == .winner)
        #expect(game.rounds.count == 2)

        let winners = game.players.filter { $0.status == .winner }
        #expect(winners.count == 1)
        #expect(winners.first?.name == DemoDataGenerator.winnerName)
        // Everyone else is eliminated.
        #expect(game.players.filter { $0.status == .eliminated }.count == 3)
    }

    // MARK: - Cleanup / duplicate protection

    @Test func clearDemoDataRemovesOnlyDemoGames() throws {
        let context = try makeContext()
        // A real game the manager created.
        let real = Game(name: "My League", season: "2025/26", allowRepeats: false)
        context.insert(real)
        // A demo game.
        _ = runFullDemo(context)

        DemoDataService.clearDemoData(context: context)

        let remaining = try context.fetch(FetchDescriptor<Game>())
        #expect(remaining.count == 1)
        #expect(remaining.first?.name == "My League")
        #expect(remaining.first?.isDemoData == false)
        // Cascade delete took the demo players/rounds/picks with it.
        #expect(try context.fetch(FetchDescriptor<Player>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Round>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Pick>()).isEmpty)
    }

    @Test func restartClearsPriorDemoDataFirst() throws {
        let context = try makeContext()
        _ = runFullDemo(context)
        // Simulate a restart: clear, then create a fresh empty demo game.
        DemoDataService.clearDemoData(context: context)
        let fresh = DemoDataService.createEmptyGame(context: context)

        let demoGames = try context.fetch(FetchDescriptor<Game>(predicate: #Predicate { $0.isDemoData }))
        #expect(demoGames.count == 1)
        #expect(demoGames.first?.id == fresh.id)
        #expect(fresh.players.isEmpty && fresh.rounds.isEmpty)
    }

    // MARK: - Generator / step sanity

    @Test func stepsAdvanceInOrderToAFinalStep() {
        #expect(DemoStep.intro.next == .players)
        // The resume tip sits between round 1's results and round 2 opening.
        #expect(DemoStep.round1Results.next == .resumeTip)
        #expect(DemoStep.resumeTip.next == .round2Open)
        #expect(DemoStep.round2Picks.next == .done)
        #expect(DemoStep.done.next == nil)
        #expect(DemoStep.done.isFinal)
        #expect(!DemoStep.intro.isFinal)
        // Both rounds stepped through, plus the resume tip: 9 stops.
        #expect(DemoStep.count == 9)
    }

    @Test func scriptedPicksReferenceRealFixtureTeams() {
        let r1Teams = Set(DemoDataGenerator.round1Fixtures.flatMap { [$0.homeTeamId, $0.awayTeamId] })
        for teamId in DemoDataGenerator.round1Picks.values {
            #expect(r1Teams.contains(teamId))
        }
        let r2Teams = Set(DemoDataGenerator.round2Fixtures.flatMap { [$0.homeTeamId, $0.awayTeamId] })
        for teamId in DemoDataGenerator.round2Picks.values {
            #expect(r2Teams.contains(teamId))
        }
        // Cached match list covers every scripted fixture id.
        let matchIds = Set(DemoDataGenerator.matches().map(\.id))
        let scriptIds = Set((DemoDataGenerator.round1Fixtures + DemoDataGenerator.round2Fixtures).map(\.matchId))
        #expect(matchIds == scriptIds)
    }

    // MARK: - Helpers

    private func player(named name: String, in game: Game) -> Player? {
        game.players.first { $0.name == name }
    }
}
