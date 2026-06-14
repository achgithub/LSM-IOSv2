import Foundation
import SwiftData

/// A Last Man Standing game. Local on-device source of truth (app-driven model).
@Model
final class Game {
    @Attribute(.unique) var id: UUID
    var name: String
    var season: String
    var statusRaw: String
    var allowRepeats: Bool
    var rolloverRuleRaw: String
    var tieRuleRaw: String
    var anonymityModeRaw: String
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \Player.game)
    var players: [Player] = []

    @Relationship(deleteRule: .cascade, inverse: \Round.game)
    var rounds: [Round] = []

    init(
        name: String,
        season: String,
        allowRepeats: Bool,
        rolloverRule: RolloverRule = .allSurvive,
        tieRule: TieRule,
        anonymityMode: AnonymityMode = .named
    ) {
        self.id = UUID()
        self.name = name
        self.season = season
        self.statusRaw = GameStatus.setup.rawValue
        self.allowRepeats = allowRepeats
        self.rolloverRuleRaw = rolloverRule.rawValue
        self.tieRuleRaw = tieRule.rawValue
        self.anonymityModeRaw = anonymityMode.rawValue
        self.createdAt = Date()
    }

    // Typed wrappers over the stored raw strings.
    var status: GameStatus {
        get { GameStatus(rawValue: statusRaw) ?? .setup }
        set { statusRaw = newValue.rawValue }
    }
    var rolloverRule: RolloverRule {
        get { RolloverRule(rawValue: rolloverRuleRaw) ?? .allSurvive }
        set { rolloverRuleRaw = newValue.rawValue }
    }
    var tieRule: TieRule {
        get { TieRule(rawValue: tieRuleRaw) ?? .rolloverRound }
        set { tieRuleRaw = newValue.rawValue }
    }
    var anonymityMode: AnonymityMode {
        get { AnonymityMode(rawValue: anonymityModeRaw) ?? .named }
        set { anonymityModeRaw = newValue.rawValue }
    }

    var activePlayers: [Player] { players.filter { $0.status == .active } }
    var currentRound: Round? { rounds.max(by: { $0.roundNumber < $1.roundNumber }) }
}
