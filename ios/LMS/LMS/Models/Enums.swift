import Foundation

/// Game lifecycle. Stored as raw strings on the SwiftData models (robust against
/// schema/predicate quirks); the models expose typed computed wrappers.
enum GameStatus: String, Codable, CaseIterable { case setup, active, complete }

enum PlayerStatus: String, Codable, CaseIterable { case active, eliminated, winner }

enum RoundStatus: String, Codable, CaseIterable { case open, picks, results, closed }

enum RoundType: String, Codable, CaseIterable, Identifiable {
    case normal, playoff, rollover
    var id: String { rawValue }
    /// Label for the open-round screen when this round is a tie follow-up.
    var openTitle: String {
        switch self {
        case .normal: return "Round"
        case .playoff: return "Playoff Round"
        case .rollover: return "Rollover Round"
        }
    }
}

enum PickResult: String, Codable, CaseIterable { case win, draw, loss, postponed }

/// What happens when everyone is eliminated in the same round (legacy field,
/// retained alongside the richer tie rules below).
enum RolloverRule: String, Codable, CaseIterable, Identifiable {
    case allSurvive = "all_survive"
    case allReenter = "all_reenter"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .allSurvive: return "All survive"
        case .allReenter: return "All re-enter"
        }
    }
}

/// The five end-game tie / all-eliminated resolution rules (spec §13c).
enum TieRule: String, Codable, CaseIterable, Identifiable {
    case split
    case rolloverRound = "rollover_round"
    case fullReset = "full_reset"
    case suddenDeath = "sudden_death"
    case longevity

    var id: String { rawValue }

    var label: String {
        switch self {
        case .split: return "Split the win"
        case .rolloverRound: return "Rollover round"
        case .fullReset: return "Full reset"
        case .suddenDeath: return "Sudden death playoff"
        case .longevity: return "Longevity tiebreaker"
        }
    }

    var detail: String {
        switch self {
        case .split: return "Joint winners, prize divided"
        case .rolloverRound: return "Void the round, everyone back in"
        case .fullReset: return "Restart from Round 1, all players reinstated"
        case .suddenDeath: return "Playoff rounds, all teams unlocked"
        case .longevity: return "Most rounds survived wins"
        }
    }
}

/// Summary-card anonymity, set once at game creation (spec §13b.2).
enum AnonymityMode: String, Codable, CaseIterable, Identifiable {
    case anonymous, named
    var id: String { rawValue }
    var label: String {
        switch self {
        case .anonymous: return "Anonymous"
        case .named: return "Named"
        }
    }
}
