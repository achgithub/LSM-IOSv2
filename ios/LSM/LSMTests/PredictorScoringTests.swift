import Testing
import Foundation
import SwiftData
@testable import LSM

/// Covers the "best enabled rung" cascade (§0): exact → goal difference →
/// result → 0, with disabled rungs skipped (not treated as 0) and draws never
/// special-cased — a correct non-exact draw should land on GD when it's on.
struct PredictorScoringTests {

    private func game(
        exact: Int = 4,
        gdEnabled: Bool = true, gdPoints: Int = 3,
        resultEnabled: Bool = true, resultPoints: Int = 2,
        jokerEnabled: Bool = false
    ) -> Game {
        Game(
            name: "Test", season: "2025/26", allowRepeats: true,
            predictorExactPoints: exact,
            predictorGDEnabled: gdEnabled, predictorGDPoints: gdPoints,
            predictorResultEnabled: resultEnabled, predictorResultPoints: resultPoints,
            predictorJokerEnabled: jokerEnabled
        )
    }

    @Test func exactScoreWinsOverEveryOtherRung() {
        let g = game()
        let points = PredictorScoringService.score(
            predictedHome: 2, predictedAway: 1, actualHome: 2, actualAway: 1, game: g
        )
        #expect(points == 4)
    }

    @Test func wrongScoreSameGoalDifferenceScoresGDRung() {
        let g = game()
        // Predicted 2-1 (GD +1), actual 3-2 (GD +1) — not exact, GD matches.
        let points = PredictorScoringService.score(
            predictedHome: 2, predictedAway: 1, actualHome: 3, actualAway: 2, game: g
        )
        #expect(points == 3)
    }

    @Test func correctResultOnlyScoresResultRung() {
        let g = game()
        // Predicted 1-0 (home win, GD +1), actual 3-0 (home win, GD +3).
        let points = PredictorScoringService.score(
            predictedHome: 1, predictedAway: 0, actualHome: 3, actualAway: 0, game: g
        )
        #expect(points == 2)
    }

    @Test func wrongResultScoresZero() {
        let g = game()
        let points = PredictorScoringService.score(
            predictedHome: 2, predictedAway: 0, actualHome: 0, actualAway: 1, game: g
        )
        #expect(points == 0)
    }

    @Test func correctNonExactDrawLandsOnGoalDifferenceNotResult() {
        let g = game()
        // Predicted 0-0, actual 2-2 — both draws (GD 0), not exact. Must land
        // on the GD rung (3pts), not silently fall through to Result.
        let points = PredictorScoringService.score(
            predictedHome: 0, predictedAway: 0, actualHome: 2, actualAway: 2, game: g
        )
        #expect(points == 3)
    }

    @Test func drawFallsThroughToResultWhenGoalDifferenceDisabled() {
        let g = game(gdEnabled: false)
        // Same correct-non-exact draw, but GD off — should cascade down to
        // the Result rung instead of scoring 0.
        let points = PredictorScoringService.score(
            predictedHome: 0, predictedAway: 0, actualHome: 2, actualAway: 2, game: g
        )
        #expect(points == 2)
    }

    @Test func disabledRungsAreSkippedNotZeroed() {
        // Both GD and Result off — only Exact can ever score.
        let g = game(gdEnabled: false, resultEnabled: false)
        let exact = PredictorScoringService.score(
            predictedHome: 1, predictedAway: 1, actualHome: 1, actualAway: 1, game: g
        )
        #expect(exact == 4)
        let gdOnly = PredictorScoringService.score(
            predictedHome: 2, predictedAway: 1, actualHome: 3, actualAway: 2, game: g
        )
        #expect(gdOnly == 0)
    }

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Game.self, Player.self, Round.self, Pick.self, Prediction.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    @Test func jokerDoublesTheAwardedRung() throws {
        let context = try makeContext()
        let g = game(jokerEnabled: true)
        context.insert(g)
        let round = Round(roundNumber: 1, deadline: .now, fixtureIds: [101], game: g)
        context.insert(round)
        let player = Player(name: "Alice", game: g)
        context.insert(player)
        let prediction = Prediction(
            fixtureId: 101, predictedHome: 2, predictedAway: 1, isJoker: true, player: player, round: round
        )
        context.insert(prediction)
        round.predictions = [prediction]

        try PredictorScoringService.closeRound(
            round, game: g, finalScores: [101: (home: 2, away: 1)], context: context
        )

        #expect(prediction.pointsAwarded == 8) // exact (4) doubled by the joker
        #expect(round.status == .closed)
    }

    @Test func jokerHasNoEffectWhenDisabledOnTheGame() throws {
        let context = try makeContext()
        let g = game(jokerEnabled: false)
        context.insert(g)
        let round = Round(roundNumber: 1, deadline: .now, fixtureIds: [101], game: g)
        context.insert(round)
        let player = Player(name: "Alice", game: g)
        context.insert(player)
        let prediction = Prediction(
            fixtureId: 101, predictedHome: 2, predictedAway: 1, isJoker: true, player: player, round: round
        )
        context.insert(prediction)
        round.predictions = [prediction]

        try PredictorScoringService.closeRound(
            round, game: g, finalScores: [101: (home: 2, away: 1)], context: context
        )

        #expect(prediction.pointsAwarded == 4) // not doubled — joker is off
    }

    @Test func saveScoresDoesNotCloseRound() throws {
        let context = try makeContext()
        let g = game()
        context.insert(g)
        let round = Round(roundNumber: 1, deadline: .now, fixtureIds: [101, 102], game: g)
        context.insert(round)
        let player = Player(name: "Alice", game: g)
        context.insert(player)
        let p1 = Prediction(fixtureId: 101, predictedHome: 1, predictedAway: 0, isJoker: false, player: player, round: round)
        let p2 = Prediction(fixtureId: 102, predictedHome: 0, predictedAway: 0, isJoker: false, player: player, round: round)
        context.insert(p1); context.insert(p2)
        round.predictions = [p1, p2]

        // Save only one fixture's score.
        PredictorScoringService.saveScores(round, finalScores: [101: (home: 2, away: 1)])

        #expect(round.status == .open)
        #expect(p1.actualHome == 2 && p1.actualAway == 1)
        #expect(p1.pointsAwarded == nil)
        #expect(p2.actualHome == nil)
    }

    @Test func closeRoundRequiresEveryFixtureScore() throws {
        let context = try makeContext()
        let g = game()
        context.insert(g)
        // Two fixtures, but only one score provided.
        let round = Round(roundNumber: 1, deadline: .now, fixtureIds: [101, 102], game: g)
        context.insert(round)
        let player = Player(name: "Alice", game: g)
        context.insert(player)
        let p1 = Prediction(fixtureId: 101, predictedHome: 1, predictedAway: 0, isJoker: false, player: player, round: round)
        context.insert(p1)
        round.predictions = [p1]

        #expect(throws: PredictorScoringError.incompleteScores) {
            try PredictorScoringService.closeRound(
                round, game: g, finalScores: [101: (home: 2, away: 1)], context: context
            )
        }
        #expect(round.status == .open)
    }

    @Test func voidedFixtureScoresZeroAndLeavesActualScoreNil() throws {
        let context = try makeContext()
        let g = game()
        context.insert(g)
        let round = Round(roundNumber: 1, deadline: .now, fixtureIds: [101, 102], game: g)
        context.insert(round)
        let player = Player(name: "Alice", game: g)
        context.insert(player)
        // Predicted 0-0 on the voided fixture — must NOT score exact points
        // against a fabricated result once it's postponed/cancelled.
        let voidedPrediction = Prediction(fixtureId: 101, predictedHome: 0, predictedAway: 0, isJoker: false, player: player, round: round)
        let playedPrediction = Prediction(fixtureId: 102, predictedHome: 1, predictedAway: 0, isJoker: false, player: player, round: round)
        context.insert(voidedPrediction); context.insert(playedPrediction)
        round.predictions = [voidedPrediction, playedPrediction]

        try PredictorScoringService.closeRound(
            round, game: g,
            finalScores: [102: (home: 1, away: 0)],
            voidFixtureIds: [101],
            context: context
        )

        #expect(round.status == .closed)
        #expect(voidedPrediction.pointsAwarded == 0)
        #expect(voidedPrediction.actualHome == nil && voidedPrediction.actualAway == nil)
        #expect(playedPrediction.pointsAwarded == g.predictorExactPoints)
    }

    @Test func closeRoundRequiresEveryFixtureScoredOrVoided() throws {
        let context = try makeContext()
        let g = game()
        context.insert(g)
        let round = Round(roundNumber: 1, deadline: .now, fixtureIds: [101, 102], game: g)
        context.insert(round)
        let player = Player(name: "Alice", game: g)
        context.insert(player)
        let p1 = Prediction(fixtureId: 101, predictedHome: 1, predictedAway: 0, isJoker: false, player: player, round: round)
        context.insert(p1)
        round.predictions = [p1]

        // Fixture 102 is neither scored nor voided — must still throw.
        #expect(throws: PredictorScoringError.incompleteScores) {
            try PredictorScoringService.closeRound(
                round, game: g, finalScores: [101: (home: 2, away: 1)], voidFixtureIds: [], context: context
            )
        }
    }

    @Test func zeroZeroCountsAsEnteredScore() throws {
        let context = try makeContext()
        let g = game()
        context.insert(g)
        let round = Round(roundNumber: 1, deadline: .now, fixtureIds: [101], game: g)
        context.insert(round)
        let player = Player(name: "Alice", game: g)
        context.insert(player)
        let p = Prediction(fixtureId: 101, predictedHome: 0, predictedAway: 0, isJoker: false, player: player, round: round)
        context.insert(p)
        round.predictions = [p]

        // 0-0 is a valid entered result — must NOT throw incompleteScores.
        try PredictorScoringService.closeRound(
            round, game: g, finalScores: [101: (home: 0, away: 0)], context: context
        )

        #expect(round.status == .closed)
        #expect(p.pointsAwarded == g.predictorExactPoints) // exact match (0-0 predicted, 0-0 actual)
    }
}
