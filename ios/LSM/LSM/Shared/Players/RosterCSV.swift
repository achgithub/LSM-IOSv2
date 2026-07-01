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

    /// Serialize members back to the same `Name` / `Name, Group` format `parse`
    /// reads. A member in multiple groups produces one row per group (mirrors
    /// how `parse` + import actually assign group membership); a member in no
    /// groups produces a single bare-name row. Round-trips name+group-membership
    /// losslessly; other fields (createdAt, token) were never carried by this
    /// format, on either side.
    static func serialize(_ members: [RosterMember]) -> String {
        members
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .flatMap { member -> [String] in
                let groupNames = member.groups.map(\.name).sorted()
                return groupNames.isEmpty ? [member.name] : groupNames.map { "\(member.name), \($0)" }
            }
            .joined(separator: "\n")
    }
}
