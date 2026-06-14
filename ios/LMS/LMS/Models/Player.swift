import Foundation
import SwiftData

/// A named player within a game. No app account — names only (spec §6.2).
/// Name uniqueness within a game is enforced in code at add time.
@Model
final class Player {
    @Attribute(.unique) var id: UUID
    var name: String
    var statusRaw: String
    var roundsSurvived: Int
    var weakPicks: Int
    /// True for the app owner's own entry in a game (spec §13b.2 transparency ⚑).
    var isManager: Bool
    var game: Game?

    @Relationship(deleteRule: .cascade, inverse: \Pick.player)
    var picks: [Pick] = []

    init(name: String, game: Game? = nil, isManager: Bool = false) {
        self.id = UUID()
        self.name = name
        self.statusRaw = PlayerStatus.active.rawValue
        self.roundsSurvived = 0
        self.weakPicks = 0
        self.isManager = isManager
        self.game = game
    }

    var status: PlayerStatus {
        get { PlayerStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }
}
