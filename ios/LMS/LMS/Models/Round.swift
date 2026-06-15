import Foundation
import SwiftData

/// One round of a game, linked to real fixture matchdays by football-data ids.
@Model
final class Round {
    @Attribute(.unique) var id: UUID
    var roundNumber: Int
    var roundTypeRaw: String
    var fixtureIds: [Int]
    var deadline: Date
    var statusRaw: String
    /// Which league these fixtures belong to (so resolution targets the right
    /// Worker and team count). Empty on rounds created before multi-league —
    /// `league` resolves that to the home league. See [[Leagues]].
    var leagueIdRaw: String = ""
    var game: Game?

    @Relationship(deleteRule: .cascade, inverse: \Pick.round)
    var picks: [Pick] = []

    init(
        roundNumber: Int,
        deadline: Date,
        fixtureIds: [Int] = [],
        roundType: RoundType = .normal,
        leagueId: String = Leagues.home.id,
        game: Game? = nil
    ) {
        self.id = UUID()
        self.roundNumber = roundNumber
        self.deadline = deadline
        self.fixtureIds = fixtureIds
        self.roundTypeRaw = roundType.rawValue
        self.statusRaw = RoundStatus.open.rawValue
        self.leagueIdRaw = leagueId
        self.game = game
    }

    /// The league this round's fixtures belong to (legacy empty → home).
    var league: LeagueOption { Leagues.resolve(leagueIdRaw) }

    var status: RoundStatus {
        get { RoundStatus(rawValue: statusRaw) ?? .open }
        set { statusRaw = newValue.rawValue }
    }
    var roundType: RoundType {
        get { RoundType(rawValue: roundTypeRaw) ?? .normal }
        set { roundTypeRaw = newValue.rawValue }
    }
}
