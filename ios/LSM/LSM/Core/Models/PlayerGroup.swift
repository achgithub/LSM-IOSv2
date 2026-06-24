import Foundation
import SwiftData

/// A named group of reusable players (e.g. "Work", "Family", "Five-a-side").
/// Many-to-many with `RosterMember` — a person can be in several groups since
/// they may play in multiple games. Used to filter who you add to a game.
@Model
final class PlayerGroup {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date

    /// The roster members in this group. Deleting a group nullifies these links
    /// (the people remain); deleting a person removes them from their groups.
    var members: [RosterMember] = []

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
    }
}
