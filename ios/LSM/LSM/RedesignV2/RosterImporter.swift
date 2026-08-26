import SwiftData

/// CSV player import — shared by `PlayersViewV2`'s IMPORT tile and
/// `RosterSettingsViewV2`'s "Import CSV" action, which are now the same
/// feature reached two ways (Roster is an inline panel inside Players — see
/// V2 audit 3.7). Inserts new (case-insensitively unique) members, resolves
/// or creates groups on the fly, and assigns each member to its per-row
/// group, falling back to `fallbackGroupName` for rows with none — only
/// `RosterSettingsViewV2` offers that fallback (its own per-import group
/// picker); `PlayersViewV2` calls this with `fallbackGroupName: nil`,
/// matching its prior behavior exactly. Callers format their own message
/// from the returned `Summary` rather than sharing one string, since the
/// two screens' messages already differed (only `RosterSettingsViewV2`
/// mentions the assignment count) and this pass isn't the place to
/// silently unify that copy.
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
