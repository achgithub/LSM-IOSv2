import Foundation
import SwiftData

/// A reusable person in the manager's address book — NOT tied to any one game.
/// Lets you quickly add the same people to new games without retyping. A per-game
/// `Player` is created from a roster member (or a typed name) when added to a game.
@Model
final class RosterMember {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date

    /// Groups this person belongs to (many-to-many; see `PlayerGroup`).
    @Relationship(inverse: \PlayerGroup.members)
    var groups: [PlayerGroup] = []

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
    }
}
