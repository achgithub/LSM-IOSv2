import Foundation
import SwiftData

/// One pick per player per round: the team that player was assigned this round.
@Model
final class Pick {
    @Attribute(.unique) var id: UUID
    var teamId: Int
    /// Which fixture this pick's team result should come from, when that team
    /// plays twice in the round (rearranged fixtures). nil for picks made
    /// before this field existed, or when the team only plays once.
    var fixtureId: Int?
    var resultRaw: String?
    var player: Player?
    var round: Round?

    init(teamId: Int, fixtureId: Int? = nil, player: Player? = nil, round: Round? = nil) {
        self.id = UUID()
        self.teamId = teamId
        self.fixtureId = fixtureId
        self.resultRaw = nil
        self.player = player
        self.round = round
    }

    /// nil until the round result is known.
    var result: PickResult? {
        get { resultRaw.flatMap(PickResult.init(rawValue:)) }
        set { resultRaw = newValue?.rawValue }
    }
}
