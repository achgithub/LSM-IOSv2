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
    /// Global submission token — one link for this player across all games.
    /// Nil until the manager mints a link. Use `submissionToken` for typed access.
    var submissionTokenRaw: String?

    var submissionToken: UUID? { submissionTokenRaw.flatMap(UUID.init) }

    /// Groups this person belongs to (many-to-many; see `PlayerGroup`).
    @Relationship(inverse: \PlayerGroup.members)
    var groups: [PlayerGroup] = []

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
    }
}
