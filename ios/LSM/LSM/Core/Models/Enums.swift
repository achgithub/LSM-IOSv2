import Foundation

/// Game lifecycle. Stored as raw strings on the SwiftData models (robust against
/// schema/predicate quirks); the models expose typed computed wrappers.
enum GameStatus: String, Codable, CaseIterable {
    case setup, active, complete
    /// Localized, user-facing label (replaces `rawValue.capitalized`).
    var label: String {
        switch self {
        case .setup:    return AppString("Setup")
        case .active:   return AppString("Active")
        case .complete: return AppString("Complete")
        }
    }
}

enum PlayerStatus: String, Codable, CaseIterable {
    case active, eliminated, winner
    var label: String {
        switch self {
        case .active:     return AppString("Active")
        case .eliminated: return AppString("Eliminated")
        case .winner:     return AppString("Winner")
        }
    }
}

enum RoundStatus: String, Codable, CaseIterable {
    case open, picks, results, closed
    var label: String {
        switch self {
        case .open:    return AppString("Open")
        case .picks:   return AppString("Picks")
        case .results: return AppString("Results")
        case .closed:  return AppString("Closed")
        }
    }
}

enum RoundType: String, Codable, CaseIterable, Identifiable {
    case normal, playoff, rollover
    var id: String { rawValue }
    /// Label for the open-round screen when this round is a tie follow-up.
    var openTitle: String {
        switch self {
        case .normal: return AppString("Round")
        case .playoff: return AppString("Playoff Round")
        case .rollover: return AppString("Rollover Round")
        }
    }
}

enum PickResult: String, Codable, CaseIterable { case win, draw, loss, postponed }

/// Per-fixture result the manager enters (or pulls from the server). Shared
/// across engines (LMS's `GameLogicService`, Killer's `KillerScoringService`).
enum FixtureOutcome: String, CaseIterable, Identifiable {
    case homeWin, draw, awayWin, postponed
    var id: String { rawValue }
    var label: String {
        switch self {
        case .homeWin: return AppString("Home Win")
        case .draw: return AppString("Draw")
        case .awayWin: return AppString("Away Win")
        case .postponed: return AppString("Postponed")
        }
    }
}

/// Summary-card anonymity, set once at game creation (spec §13b.2).
enum AnonymityMode: String, Codable, CaseIterable, Identifiable {
    case anonymous, named
    var id: String { rawValue }
    var label: String {
        switch self {
        case .anonymous: return AppString("Anonymous")
        case .named: return AppString("Named")
        }
    }
}
