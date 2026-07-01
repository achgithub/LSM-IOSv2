import Foundation
import SwiftData

/// Creates and tears down tutorial content through the same persistence layer
/// and services real games use. Covers both LMS and Predictor tutorials.
@MainActor
enum TutorialDataService {

    // MARK: - Cache seeding

    /// Seed the demo league into the on-disk cache so all screens serve team
    /// names, fixtures and standings locally with no network call.
    static func seedLeagueCaches() {
        let key = Leagues.demoLeagueId
        let now = Date()
        LeagueDataCache.save(
            LeagueDataCache.Teams(date: now, items: TutorialDataGenerator.teams()),
            key: LeagueDataCache.teamsKey(key)
        )
        LeagueDataCache.save(
            LeagueDataCache.Matches(date: now, items: TutorialDataGenerator.matches()),
            key: LeagueDataCache.matchesKey(key)
        )
        LeagueDataCache.save(
            LeagueDataCache.Standings(date: now,
                                      rows: TutorialDataGenerator.standings(),
                                      teams: TutorialDataGenerator.teams()),
            key: LeagueDataCache.standingsKey(key)
        )
    }

    // MARK: - Cleanup

    static func clearTutorialData(context: ModelContext) {
        let descriptor = FetchDescriptor<Game>(predicate: #Predicate { $0.isDemoData })
        guard let games = try? context.fetch(descriptor) else { return }
        for game in games { GameLogicService.deleteGame(game, context: context) }
    }

    // MARK: - Shared player seeding

    static func addPlayers(to game: Game, context: ModelContext) {
        for name in TutorialDataGenerator.playerNames {
            let player = Player(name: name, game: game, entryNumber: game.nextEntryNumber)
            context.insert(player)
            game.players.append(player)
        }
    }

    // MARK: - LMS tutorial

    @discardableResult
    static func createLMSGame(context: ModelContext) -> Game {
        let game = Game(
            name: AppString("Tutorial Game"),
            season: Leagues.app.season,
            allowRepeats: false,
            anonymityMode: .named,
            leagueIds: [Leagues.demoLeagueId],
            isDemoData: true,
            mode: .lms
        )
        context.insert(game)
        return game
    }

    @discardableResult
    static func openLMSRound1(in game: Game, context: ModelContext) -> Round {
        let ids = TutorialDataGenerator.lmsRound1Fixtures.map(\.matchId)
        return GameLogicService.openRound(
            in: game, fixtureIds: ids,
            deadline: Date().addingTimeInterval(-4 * 24 * 3600),
            roundType: .normal, context: context
        )
    }

    static func assignLMSRound1Picks(game: Game, round: Round, context: ModelContext) {
        assignPicks(TutorialDataGenerator.lmsRound1Picks, game: game, round: round, context: context)
    }

    static func closeLMSRound1(game: Game, round: Round, context: ModelContext) {
        applyResults(TutorialDataGenerator.lmsRound1Fixtures, to: round)
        GameLogicService.closeRound(round, game: game, context: context)
    }

    @discardableResult
    static func openLMSRound2(in game: Game, context: ModelContext) -> Round {
        let ids = TutorialDataGenerator.lmsRound2Fixtures.map(\.matchId)
        return GameLogicService.openRound(
            in: game, fixtureIds: ids,
            deadline: Date().addingTimeInterval(-2 * 24 * 3600),
            roundType: .normal, context: context
        )
    }

    static func assignLMSRound2Picks(game: Game, round: Round, context: ModelContext) {
        assignPicks(TutorialDataGenerator.lmsRound2Picks, game: game, round: round, context: context)
    }

    static func closeLMSRound2AndDeclareWinner(game: Game, round: Round, context: ModelContext) {
        applyResults(TutorialDataGenerator.lmsRound2Fixtures, to: round)
        GameLogicService.closeRound(round, game: game, context: context)
        let winnerIds = game.activePlayers.map(\.id)
        if !winnerIds.isEmpty { GameLogicService.apply(.winners(winnerIds), game: game) }
    }

    private static func assignPicks(_ picks: [String: Int], game: Game, round: Round, context: ModelContext) {
        for player in game.activePlayers {
            guard let teamId = picks[player.name] else { continue }
            GameLogicService.setPick(player: player, round: round, teamId: teamId, context: context)
        }
    }

    private static func applyResults(_ fixtures: [TutorialDataGenerator.ScriptedFixture], to round: Round) {
        for f in fixtures {
            GameLogicService.applyResult(
                fixtureId: f.matchId,
                homeTeamId: f.homeTeamId, awayTeamId: f.awayTeamId,
                outcome: f.outcome, round: round
            )
        }
    }

    // MARK: - Predictor tutorial

    @discardableResult
    static func createPredictorGame(context: ModelContext) -> Game {
        let game = Game(
            name: AppString("Tutorial Predictor"),
            season: Leagues.app.season,
            allowRepeats: true,
            leagueIds: [Leagues.demoLeagueId],
            isDemoData: true,
            mode: .predictor
        )
        context.insert(game)
        return game
    }

    @discardableResult
    static func openPredictorRound(in game: Game, context: ModelContext) -> Round {
        let ids = TutorialDataGenerator.predictorFixtures.map(\.matchId)
        return GameLogicService.openRound(
            in: game, fixtureIds: ids,
            deadline: Date().addingTimeInterval(-1 * 24 * 3600),
            roundType: .normal, context: context
        )
    }

    /// Seeds predictions for all players. The user's chosen score overrides the
    /// scripted prediction for Alex on fixture 8008 (the one they entered).
    static func seedPredictorPredictions(
        game: Game, round: Round,
        userHome: Int, userAway: Int,
        context: ModelContext
    ) {
        let userFixtureId = TutorialDataGenerator.predictorFirstMatchId
        for player in game.players {
            guard let script = TutorialDataGenerator.predictorScriptedPredictions[player.name] else { continue }
            for fixture in TutorialDataGenerator.predictorFixtures {
                let home: Int
                let away: Int
                if player.name == "Alex" && fixture.matchId == userFixtureId {
                    home = userHome
                    away = userAway
                } else {
                    home = script[fixture.matchId]?.home ?? 1
                    away = script[fixture.matchId]?.away ?? 0
                }
                PredictorScoringService.setPrediction(
                    player: player, round: round,
                    fixtureId: fixture.matchId, home: home, away: away,
                    context: context
                )
            }
        }
    }

    static func closePredictorRound(game: Game, round: Round, context: ModelContext) throws {
        let finalScores = Dictionary(uniqueKeysWithValues: TutorialDataGenerator.predictorFixtures.map {
            ($0.matchId, (home: $0.homeScore ?? 0, away: $0.awayScore ?? 0))
        })
        try PredictorScoringService.closeRound(round, game: game, finalScores: finalScores, context: context)
    }
}
