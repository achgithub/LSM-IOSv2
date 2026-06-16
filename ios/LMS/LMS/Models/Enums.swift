import Foundation

/// Game lifecycle. Stored as raw strings on the SwiftData models (robust against
/// schema/predicate quirks); the models expose typed computed wrappers.
enum GameStatus: String, Codable, CaseIterable {
    case setup, active, complete
    /// Localized, user-facing label (replaces `rawValue.capitalized`).
    var label: String {
        switch self {
        case .setup:    return String(localized: "Setup")
        case .active:   return String(localized: "Active")
        case .complete: return String(localized: "Complete")
        }
    }
}

enum PlayerStatus: String, Codable, CaseIterable {
    case active, eliminated, winner
    var label: String {
        switch self {
        case .active:     return String(localized: "Active")
        case .eliminated: return String(localized: "Eliminated")
        case .winner:     return String(localized: "Winner")
        }
    }
}

enum RoundStatus: String, Codable, CaseIterable {
    case open, picks, results, closed
    var label: String {
        switch self {
        case .open:    return String(localized: "Open")
        case .picks:   return String(localized: "Picks")
        case .results: return String(localized: "Results")
        case .closed:  return String(localized: "Closed")
        }
    }
}

enum RoundType: String, Codable, CaseIterable, Identifiable {
    case normal, playoff, rollover
    var id: String { rawValue }
    /// Label for the open-round screen when this round is a tie follow-up.
    var openTitle: String {
        switch self {
        case .normal: return String(localized: "Round")
        case .playoff: return String(localized: "Playoff Round")
        case .rollover: return String(localized: "Rollover Round")
        }
    }
}

enum PickResult: String, Codable, CaseIterable { case win, draw, loss, postponed }

/// Summary-card anonymity, set once at game creation (spec §13b.2).
enum AnonymityMode: String, Codable, CaseIterable, Identifiable {
    case anonymous, named
    var id: String { rawValue }
    var label: String {
        switch self {
        case .anonymous: return String(localized: "Anonymous")
        case .named: return String(localized: "Named")
        }
    }
}
