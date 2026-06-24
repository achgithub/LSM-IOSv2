import Foundation
import SwiftData

/// Creates and tears down demo content **through the same persistence layer and
/// services real games use** — never by reaching around them. SwiftData records
/// (`Game`, `Player`, `Round`, `Pick`) are inserted via the model context exactly
/// as `NewGameView`/`AddPlayersView` do, and all round/pick/result/close logic
/// goes through `GameLogicService`, so the demo exercises the real code paths
/// rather than a parallel mock.
///
/// The only demo-specific plumbing is reference data: the demo league's teams,
/// fixtures and standings are seeded into the ordinary on-disk league cache
/// (`LeagueDataCache`) — the same cache a real first-launch free-fill writes — so
/// every screen finds them locally with no network. That league
/// (`Leagues.demo`) is never offered in any user-facing picker.
@MainActor
enum DemoDataService {

    // MARK: - Reference data (local cache seed)

    /// Seed the demo league's teams / matches / standings into the on-disk cache
    /// with a current timestamp, so cache-first reads (`LeagueData.load`) serve
    /// them locally and never call a Worker. Idempotent — safe to call on every
    /// demo start.
    static func seedLeagueCaches() {
        let leagueId = Leagues.demoLeagueId
        let now = Date()
        LeagueDataCache.save(
            LeagueDataCache.Teams(date: now, items: DemoDataGenerator.teams()),
            key: LeagueDataCache.teamsKey(leagueId)
        )
        LeagueDataCache.save(
            LeagueDataCache.Matches(date: now, items: DemoDataGenerator.matches()),
            key: LeagueDataCache.matchesKey(leagueId)
        )
        LeagueDataCache.save(
            LeagueDataCache.Standings(date: now, rows: DemoDataGenerator.standings(), teams: DemoDataGenerator.teams()),
            key: LeagueDataCache.standingsKey(leagueId)
        )
    }

    // MARK: - Cleanup / duplicate protection

    /// Delete every demo game (and, by cascade delete, its players/rounds/picks).
    /// Called before a (re)start so the demo can never accumulate duplicates, and
    /// on exit/clear. Real games (`isDemoData == false`) are never touched.
    static func clearDemoData(context: ModelContext) {
        let descriptor = FetchDescriptor<Game>(predicate: #Predicate { $0.isDemoData })
        guard let demoGames = try? context.fetch(descriptor) else { return }
        for game in demoGames { context.delete(game) }
    }

    // MARK: - Step 1: empty game

    /// Create the empty demo game (status `.setup`, no players) — the starting
    /// point the user watches fill up. Marked `isDemoData` so it can be cleared.
    @discardableResult
    static func createEmptyGame(context: ModelContext) -> Game {
        let game = Game(
            name: AppString("Demo Game"),
            season: Leagues.app.season,
            allowRepeats: false,
            anonymityMode: .named,
            leagueIds: [Leagues.demoLeagueId],
            isDemoData: true
        )
        context.insert(game)
        return game
    }

    // MARK: - Step 2: players

    /// Add the sample players to the game (same path as adding from the roster).
    static func addPlayers(to game: Game, context: ModelContext) {
        for name in DemoDataGenerator.playerNames {
            let player = Player(name: name, game: game, entryNumber: game.nextEntryNumber)
            context.insert(player)
            game.players.append(player)
        }
    }

    // MARK: - Step 3: open round 1

    @discardableResult
    static func openRound1(in game: Game, context: ModelContext) -> Round {
        let fixtureIds = DemoDataGenerator.round1Fixtures.map(\.matchId)
        // 24h before the (back-dated) kickoffs — value is cosmetic here.
        let deadline = Date().addingTimeInterval(-4 * 24 * 3600)
        return GameLogicService.openRound(
            in: game, fixtureIds: fixtureIds, deadline: deadline, roundType: .normal, context: context
        )
    }

    // MARK: - Step 4: assign round 1 picks

    static func assignRound1Picks(game: Game, round: Round, context: ModelContext) {
        assignPicks(DemoDataGenerator.round1Picks, game: game, round: round, context: context)
    }

    // MARK: - Step 5: round 1 results & close

    static func closeRound1(game: Game, round: Round, context: ModelContext) {
        applyResults(DemoDataGenerator.round1Fixtures, to: round)
        GameLogicService.closeRound(round, game: game, context: context)
    }

    // MARK: - Step 6: open round 2 (survivors only)

    @discardableResult
    static func openRound2(in game: Game, context: ModelContext) -> Round {
        let fixtureIds = DemoDataGenerator.round2Fixtures.map(\.matchId)
        let deadline = Date().addingTimeInterval(-2 * 24 * 3600)
        return GameLogicService.openRound(
            in: game, fixtureIds: fixtureIds, deadline: deadline, roundType: .normal, context: context
        )
    }

    // MARK: - Step 7: assign round 2 picks

    static func assignRound2Picks(game: Game, round: Round, context: ModelContext) {
        assignPicks(DemoDataGenerator.round2Picks, game: game, round: round, context: context)
    }

    // MARK: - Step 8: round 2 results, close, and declare the winner

    /// Set round 2 results, close, then declare the sole survivor the winner
    /// (completing the game) — the same `apply(.winners:)` service path
    /// `DeclareWinnersView` uses. Falls back to whoever's still active if the
    /// script ever drifts.
    static func closeRound2AndDeclareWinner(game: Game, round: Round, context: ModelContext) {
        applyResults(DemoDataGenerator.round2Fixtures, to: round)
        GameLogicService.closeRound(round, game: game, context: context)
        let winnerIds = game.activePlayers.map(\.id)
        if !winnerIds.isEmpty {
            GameLogicService.apply(.winners(winnerIds), game: game)
        }
    }

    // MARK: - Shared helpers

    /// Assign picks from a name→teamId map via the real `setPick` service.
    private static func assignPicks(_ picks: [String: Int], game: Game, round: Round, context: ModelContext) {
        for player in game.activePlayers {
            guard let teamId = picks[player.name] else { continue }
            GameLogicService.setPick(player: player, round: round, teamId: teamId, context: context)
        }
    }

    /// Feed each scripted fixture's outcome through the real `applyResult` service.
    private static func applyResults(_ fixtures: [DemoDataGenerator.ScriptedFixture], to round: Round) {
        for fixture in fixtures {
            GameLogicService.applyResult(
                homeTeamId: fixture.homeTeamId,
                awayTeamId: fixture.awayTeamId,
                outcome: fixture.outcome,
                round: round
            )
        }
    }
}
