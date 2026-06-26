import Foundation
import SwiftData

/// Predictor scoring: a "best enabled rung" cascade (§0 of the architecture
/// doc). Kept separate from `GameLogicService`/`GameEngine` — Predictor has no
/// elimination, ties or tie-resolution, so threading it through that LMS
/// engine would only add conditionals to logic that doesn't apply.
enum PredictorScoringService {

    // MARK: - Predictions

    static func predictions(for player: Player, in round: Round) -> [Prediction] {
        round.predictions.filter { $0.player?.id == player.id }
    }

    static func prediction(for player: Player, fixtureId: Int, in round: Round) -> Prediction? {
        round.predictions.first { $0.player?.id == player.id && $0.fixtureId == fixtureId }
    }

    /// Set or change a player's predicted score for one fixture in a round.
    /// Mirrors `GameLogicService.setPick`'s delete-and-recreate approach —
    /// inserting a fresh `Prediction` updates synchronously, where mutating an
    /// existing one's properties in place doesn't reliably propagate at once.
    static func setPrediction( // swiftlint:disable:this function_parameter_count
        player: Player,
        round: Round,
        fixtureId: Int,
        home: Int,
        away: Int,
        context: ModelContext
    ) {
        let isJoker = prediction(for: player, fixtureId: fixtureId, in: round)?.isJoker ?? false
        if let existing = prediction(for: player, fixtureId: fixtureId, in: round) {
            context.delete(existing)
        }
        let new = Prediction(fixtureId: fixtureId, predictedHome: home, predictedAway: away, isJoker: isJoker)
        context.insert(new)
        new.player = player
        new.round = round
    }

    /// Designate one fixture as a player's joker for the round, clearing any
    /// other joker they'd set (at most one per player per round).
    static func setJoker(player: Player, round: Round, fixtureId: Int) {
        for p in predictions(for: player, in: round) {
            p.isJoker = (p.fixtureId == fixtureId)
        }
    }

    /// Points for one prediction against the real final score. The cascade
    /// falls through disabled rungs rather than special-casing draws: a
    /// correct non-exact draw has goal difference 0 either way, so it lands on
    /// the GD rung when enabled, the Result rung if GD is off, or scores 0 if
    /// both are off.
    static func score(
        predictedHome: Int,
        predictedAway: Int,
        actualHome: Int,
        actualAway: Int,
        game: Game
    ) -> Int {
        if predictedHome == actualHome && predictedAway == actualAway {
            return game.predictorExactPoints
        }
        let predictedGD = predictedHome - predictedAway
        let actualGD = actualHome - actualAway
        if game.predictorGDEnabled && predictedGD == actualGD {
            return game.predictorGDPoints
        }
        if game.predictorResultEnabled && outcome(predictedGD) == outcome(actualGD) {
            return game.predictorResultPoints
        }
        return 0
    }

    private static func outcome(_ goalDifference: Int) -> PickResult {
        if goalDifference > 0 { return .win }
        if goalDifference < 0 { return .loss }
        return .draw
    }

    /// Apply final scores to every `Prediction` in the round, score them, and
    /// close the round. `finalScores` maps fixture id → (home, away) goals for
    /// every fixture the manager entered a result for.
    static func closeRound(
        _ round: Round,
        game: Game,
        finalScores: [Int: (home: Int, away: Int)],
        context: ModelContext
    ) {
        for prediction in round.predictions {
            guard let final = finalScores[prediction.fixtureId] else { continue }
            prediction.actualHome = final.home
            prediction.actualAway = final.away
            var points = score(
                predictedHome: prediction.predictedHome,
                predictedAway: prediction.predictedAway,
                actualHome: final.home,
                actualAway: final.away,
                game: game
            )
            if prediction.isJoker && game.predictorJokerEnabled {
                points *= 2
            }
            prediction.pointsAwarded = points
        }
        round.status = .closed
        if game.status == .setup { game.status = .active }
    }
}
