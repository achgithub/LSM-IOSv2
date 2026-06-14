import Foundation

/// CSV parsing for the player roster import (Players tab). Pure and testable.
nonisolated enum RosterCSV {
    /// One parsed row: a player name and, optionally, the group they belong to.
    struct Row: Equatable {
        let name: String
        let group: String?
    }

    /// Parse the file into rows. Format: `Name` or `Name, Group` (one per row).
    /// The group is the first field after the name that isn't an email — so the
    /// legacy `Name, Email` form still works (the email is ignored, no group),
    /// and `Name, Email, Group` also resolves the group. Whitespace is trimmed
    /// and blank rows are dropped.
    static func parse(_ text: String) -> [Row] {
        text.split(whereSeparator: \.isNewline).compactMap { line -> Row? in
            let fields = line
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard let name = fields.first, !name.isEmpty else { return nil }
            let group = fields.dropFirst().first { !$0.contains("@") }
            return Row(name: name, group: group)
        }
    }
}
