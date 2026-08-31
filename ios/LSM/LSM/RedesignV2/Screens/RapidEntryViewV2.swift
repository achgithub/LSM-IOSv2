import SwiftUI
import SwiftData

/// Full-screen quick-add for the player roster — a spreadsheet-style grid
/// (name + group per row) instead of the ADD tile's one-at-a-time alert or a
/// free-text paste box. Each row's group is a dropdown (existing groups, or
/// create one on the fly) with a fill-handle to copy one row's group down
/// over every row below it in one tap, spreadsheet-style, for fast bulk
/// assignment. Inserts straight into the same roster/group models
/// `RosterImporter` uses elsewhere — this view has its own save path
/// (row-level duplicate highlighting doesn't map onto
/// `RosterImporter.Summary`), not a shared call.
struct RapidEntryViewV2: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \RosterMember.name) private var members: [RosterMember]
    @Query(sort: \PlayerGroup.name) private var groups: [PlayerGroup]

    private struct EntryRow: Identifiable {
        let id = UUID()
        var name = ""
        var groupId: UUID?
    }

    @State private var rows: [EntryRow] = (0..<14).map { _ in EntryRow() }
    @State private var newGroupRowId: UUID?
    @State private var newGroupName = ""
    @State private var summary: String?

    private let rowHeight: CGFloat = 44

    var body: some View {
        // No NavigationStack — this screen never pushes anything, and
        // .navigationTitle/.toolbar inside a fullScreenCover was reserving a
        // large blank area above the content. A plain hand-rolled header
        // sidesteps that entirely.
        //
        // Single ScrollView + single LazyVStack for everything (header
        // included), footer pinned via .safeAreaInset — the same structure
        // MatchesViewV2 already uses successfully, not a hand-rolled
        // nested-VStack-plus-.frame(maxHeight:) layout. That variant measured
        // out to two large, unexplained gaps between sections; this one
        // doesn't need explaining because it's the proven pattern.
        ScrollView {
            LazyVStack(spacing: 0) {
                header
                // One floating surface for the whole grid, not a card per
                // row — keeps the compact spreadsheet layout (see this
                // file's top doc comment for why that's deliberate) while
                // still reading as a V2 card-over-photo surface instead of
                // floating loose on the background.
                VStack(spacing: 0) {
                    gridHeader
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        gridRow(index: index, row: row)
                    }
                }
                .v2FloatingCard()
                .padding(.horizontal, V2Theme.Spacing.horizontal)
            }
        }
        .v2TeamRoomScene()
        .safeAreaInset(edge: .bottom) { footer }
        .alert("New group", isPresented: Binding(get: { newGroupRowId != nil }, set: { if !$0 { newGroupRowId = nil } })) {
            TextField("Group name", text: $newGroupName)
            Button("Add", action: commitNewGroup)
            Button("Cancel", role: .cancel) { newGroupRowId = nil }
        }
    }

    private var footer: some View {
        VStack(spacing: 8) {
            if let summary {
                Text(summary)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(V2Theme.accent)
            }
            HStack(spacing: 10) {
                Button {
                    rows.append(EntryRow())
                } label: {
                    Label("Add Row", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .tint(V2Theme.textSecondary)

                Button("Add All", action: addAll)
                    .buttonStyle(.borderedProminent)
                    .tint(V2Theme.accent)
                    .frame(maxWidth: .infinity)
                    .disabled(!hasSaveableRow)
            }
        }
        .padding(.horizontal, V2Theme.Spacing.horizontal)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    private var header: some View {
        HStack {
            Text("Rapid Entry")
                .font(.title3.weight(.bold))
                .foregroundStyle(V2Theme.textPrimary)
            Spacer()
            Button("Done") { dismiss() }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(V2Theme.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(V2Theme.cardBackground, in: Capsule())
        }
        .padding(.horizontal, V2Theme.Spacing.horizontal)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private var gridHeader: some View {
        HStack(spacing: 0) {
            Text("NAME")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("GROUP")
                .frame(width: 140, alignment: .leading)
            Color.clear.frame(width: 28)
        }
        .font(.caption2.weight(.bold))
        .foregroundStyle(V2Theme.textTertiary)
        .padding(.horizontal, V2Theme.Spacing.horizontal)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func gridRow(index: Int, row: EntryRow) -> some View {
        let duplicate = isDuplicate(at: index)
        HStack(spacing: 0) {
            TextField("Player \(index + 1)", text: binding(for: row.id, \.name))
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
            groupMenu(for: row)
                .frame(width: 140, alignment: .leading)
            fillHandle(index: index, row: row)
                .frame(width: 28)
        }
        .padding(.horizontal, V2Theme.Spacing.horizontal)
        .frame(height: rowHeight)
        .background(duplicate ? V2Theme.danger.opacity(0.16) : Color.clear)
        .overlay(alignment: .bottom) {
            Rectangle().fill(V2Theme.textTertiary.opacity(0.15)).frame(height: 1)
        }
    }

    private func groupMenu(for row: EntryRow) -> some View {
        Menu {
            Button("No group") { setGroup(nil, for: row.id) }
            ForEach(groups) { group in
                Button(group.name) { setGroup(group.id, for: row.id) }
            }
            Divider()
            Button("Add Group…") { newGroupRowId = row.id; newGroupName = "" }
        } label: {
            HStack(spacing: 4) {
                Text(groupName(row.groupId) ?? "No group")
                    .font(.caption)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
            .foregroundStyle(V2Theme.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(V2Theme.pillBackground, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }

    /// Tap to copy this row's group onto every row below it, spreadsheet
    /// fill-handle style — a tap instead of a drag because a drag gesture on
    /// a small target inside a `ScrollView` is fighting the scroll view's
    /// own pan recognizer for every point of movement, and kept truncating
    /// after a row or two no matter how the gesture was prioritized. A tap
    /// has no such ambiguity and does the same job: populate everything
    /// below in one motion.
    private func fillHandle(index: Int, row: EntryRow) -> some View {
        Button {
            guard index < rows.count - 1 else { return }
            for i in (index + 1)..<rows.count { rows[i].groupId = row.groupId }
        } label: {
            Image(systemName: "arrow.down.square")
                .font(.caption)
                .foregroundStyle(V2Theme.textTertiary)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .disabled(index >= rows.count - 1)
    }

    private func binding(for id: UUID, _ keyPath: WritableKeyPath<EntryRow, String>) -> Binding<String> {
        Binding(
            get: { rows.first { $0.id == id }?[keyPath: keyPath] ?? "" },
            set: { newValue in
                guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
                rows[index][keyPath: keyPath] = newValue
                growIfNeeded()
            }
        )
    }

    /// Keeps one trailing blank row always available, like a spreadsheet.
    private func growIfNeeded() {
        guard let last = rows.last, !last.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        rows.append(EntryRow())
    }

    private func setGroup(_ groupId: UUID?, for rowId: UUID) {
        guard let index = rows.firstIndex(where: { $0.id == rowId }) else { return }
        rows[index].groupId = groupId
    }

    private func groupName(_ id: UUID?) -> String? {
        guard let id else { return nil }
        return groups.first { $0.id == id }?.name
    }

    /// Only an *earlier* row with the same name counts as the duplicate, so
    /// of several rows typed with one name, the first is still saveable.
    private func isDuplicate(at index: Int) -> Bool {
        let name = rows[index].name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return false }
        if members.contains(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) { return true }
        return rows[..<index].contains {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines).localizedCaseInsensitiveCompare(name) == .orderedSame
        }
    }

    private var hasSaveableRow: Bool {
        rows.enumerated().contains { index, row in
            !row.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isDuplicate(at: index)
        }
    }

    private func commitNewGroup() {
        defer { newGroupRowId = nil }
        guard let rowId = newGroupRowId else { return }
        let name = newGroupName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        if let existing = groups.first(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
            setGroup(existing.id, for: rowId)
            return
        }
        let group = PlayerGroup(name: name)
        context.insert(group)
        setGroup(group.id, for: rowId)
    }

    private func addAll() {
        var added = 0
        var survivors: [EntryRow] = []
        for (index, row) in rows.enumerated() {
            let name = row.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            guard !isDuplicate(at: index) else {
                survivors.append(row)
                continue
            }
            let member = RosterMember(name: name)
            context.insert(member)
            if let groupId = row.groupId, let group = groups.first(where: { $0.id == groupId }) {
                member.groups.append(group)
            }
            added += 1
        }

        rows = survivors + [EntryRow()]

        if added > 0 && survivors.isEmpty {
            summary = added == 1 ? AppString("Added 1 player.") : AppString("Added \(added) players.")
        } else if added > 0 {
            summary = AppString("Added \(added), \(survivors.count) duplicate\(survivors.count == 1 ? "" : "s") left for you to fix.")
        } else if !survivors.isEmpty {
            summary = AppString("All duplicates — fix the highlighted names and try again.")
        } else {
            summary = nil
        }
    }
}
