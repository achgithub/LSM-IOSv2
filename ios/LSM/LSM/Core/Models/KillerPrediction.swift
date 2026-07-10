import Foundation
import SwiftData

/// One Killer prediction: a player's Home/Draw/Away guess for one Manager
/// Picked Game (MPG) in one round, plus — Kill Phase only — the Hit target
/// that guess is linked to. Not a reuse of `Prediction` (Predictor's model is
/// score-based; this is outcome-based and carries the Hit-target concept
/// Predictor has no analog for).
@Model
final class KillerPrediction {
    @Attribute(.unique) var id: UUID
    var fixtureId: Int
    var predictedOutcomeRaw: String
    /// nil until the round closes and the real result is applied.
    var actualOutcomeRaw: String?
    /// nil until scored at round close; stays nil forever if the fixture
    /// was voided (a void is a non-event, not a fabricated correct/incorrect).
    var wasCorrect: Bool?
    /// Kill Phase only — nil in the Build Phase. Which opponent this MPG's
    /// Hit targets, if any.
    var hitTargetPlayerId: UUID?
    /// nil until scored at round close. True only if `wasCorrect` and the
    /// fixture wasn't voided.
    var hitLanded: Bool?
    var player: Player?
    var round: Round?

    init(
        fixtureId: Int,
        predictedOutcome: FixtureOutcome,
        hitTargetPlayerId: UUID? = nil,
        player: Player? = nil,
        round: Round? = nil
    ) {
        self.id = UUID()
        self.fixtureId = fixtureId
        self.predictedOutcomeRaw = predictedOutcome.rawValue
        self.hitTargetPlayerId = hitTargetPlayerId
        self.player = player
        self.round = round
    }

    var predictedOutcome: FixtureOutcome {
        get { FixtureOutcome(rawValue: predictedOutcomeRaw) ?? .homeWin }
        set { predictedOutcomeRaw = newValue.rawValue }
    }
    var actualOutcome: FixtureOutcome? {
        get { actualOutcomeRaw.flatMap(FixtureOutcome.init(rawValue:)) }
        set { actualOutcomeRaw = newValue?.rawValue }
    }
}
