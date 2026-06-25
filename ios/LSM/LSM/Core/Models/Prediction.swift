import Foundation
import SwiftData

/// One Predictor prediction: a player's predicted score for one fixture in one
/// round. Unlike `Pick` (one per player per round), a player has one
/// `Prediction` per fixture in the round's scope — a whole slate.
@Model
final class Prediction {
    @Attribute(.unique) var id: UUID
    var fixtureId: Int
    var predictedHome: Int
    var predictedAway: Int
    /// nil until the round closes and the real result is applied.
    var actualHome: Int?
    var actualAway: Int?
    /// nil until scored at round close.
    var pointsAwarded: Int?
    /// This player's chosen double-points fixture for the round (only
    /// meaningful when the game's `predictorJokerEnabled` is on; at most one
    /// `true` per player per round).
    var isJoker: Bool = false
    var player: Player?
    var round: Round?

    init(
        fixtureId: Int,
        predictedHome: Int,
        predictedAway: Int,
        isJoker: Bool = false,
        player: Player? = nil,
        round: Round? = nil
    ) {
        self.id = UUID()
        self.fixtureId = fixtureId
        self.predictedHome = predictedHome
        self.predictedAway = predictedAway
        self.isJoker = isJoker
        self.player = player
        self.round = round
    }
}
