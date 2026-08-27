import SwiftData

/// CSV/paste player import — shared by `RosterSettingsViewV2`'s "Import CSV"
/// action (file-based) and `RapidEntryViewV2`'s "Add All" (typed/pasted text,
/// same `RosterCSV.parse` line format). `PlayersViewV2`'s own top-level
/// IMPORT/EXPORT tiles were removed in the V2 simplification pass — CSV
/// import/export now lives solely in ROSTER's card, which already had the
/// more capable, group-scoped version (a per-import fallback-group picker;
/// both current callers use it). Callers format their own message from the
/// returned `Summary` rather than sharing one string, since the two
/// screens' messages differ (only `RosterSettingsViewV2` mentions the
/// assignment count) and this pass isn't the place to silently unify that
/// copy.
enum RosterImporter {
    struct Summary {
        let added: Int
        let skipped: Int
        let assigned: Int
    }

    static func importRows(
        _ rows: [RosterCSV.Row],
        existingMembers: [RosterMember],
        existingGroups: [PlayerGroup],
        fallbackGroupName: String? = nil,
        context: ModelContext
    ) -> Summary {
        var membersByName = Dictionary(existingMembers.map { ($0.name.lowercased(), $0) }, uniquingKeysWith: { a, _ in a })
        var groupsByName = Dictionary(existingGroups.map { ($0.name.lowercased(), $0) }, uniquingKeysWith: { a, _ in a })

        func resolveGroup(_ name: String) -> PlayerGroup {
            let key = name.lowercased()
            if let existing = groupsByName[key] { return existing }
            let created = PlayerGroup(name: name)
            context.insert(created)
            groupsByName[key] = created
            return created
        }

        var added = 0, skipped = 0, assigned = 0
        for row in rows {
            let key = row.name.lowercased()
            let member: RosterMember
            if let existing = membersByName[key] {
                member = existing
                skipped += 1
            } else {
                member = RosterMember(name: row.name)
                context.insert(member)
                membersByName[key] = member
                added += 1
            }

            if let groupName = row.group ?? fallbackGroupName {
                let group = resolveGroup(groupName)
                if !member.groups.contains(where: { $0.id == group.id }) {
                    member.groups.append(group)
                    assigned += 1
                }
            }
        }

        return Summary(added: added, skipped: skipped, assigned: assigned)
    }
}
