import Foundation
import SwiftData

/// Per-player-per-game numeric state for Killer mode. Deliberately a side
/// model rather than fields bolted onto the shared `Player` — no other mode
/// needs numeric per-player state, so this keeps that concern isolated.
/// Elimination itself stays on `Player.status` (not duplicated here), so
/// `Game.activePlayers` and winner detection keep working unchanged across
/// all three modes.
@Model
final class KillerPlayerState {
    @Attribute(.unique) var id: UUID
    /// Starts at 1 (the spec's starting life).
    var lives: Int
    /// Tracks lives gained during the Build Phase separately from `lives`,
    /// so the `killerMaxAdditionalLives` cap can be enforced explicitly
    /// without reverse-engineering it from the current total.
    var additionalLivesGained: Int
    /// Accuracy Table running total: correct MPG predictions across the
    /// whole game (both phases). Used only as an end-of-game tiebreak.
    var correctPredictions: Int
    /// Secondary end-of-game tiebreak, used only if the Accuracy Table is
    /// also tied.
    var successfulHitsLanded: Int
    var player: Player?
    var game: Game?

    init(player: Player? = nil, game: Game? = nil) {
        self.id = UUID()
        self.lives = 1
        self.additionalLivesGained = 0
        self.correctPredictions = 0
        self.successfulHitsLanded = 0
        self.player = player
        self.game = game
    }
}
