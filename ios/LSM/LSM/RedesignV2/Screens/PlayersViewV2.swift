import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Card-based restyle of `PlayersView` — same roster data/filtering, pushed
/// into an existing NavigationStack (no `List`, no embedded NavigationStack).
/// Row tap still pushes `PlayerDetailViewV2` (see that file for the detail
/// restyle) — unlike ROSTER below, it isn't inlined here yet, since that
/// screen is also pushed from three game-detail screens and calls
/// `dismiss()` on its own Remove Player flow, which would pop this screen
/// instead of just collapsing an inline panel if embedded as-is.
struct PlayersViewV2: View {
    @Environment(\.modelContext) private var context
    @Environment(Entitlements.self) private var entitlements
    @Query(sort: \RosterMember.name) private var members: [RosterMember]
    @Query(sort: \PlayerGroup.name) private var groups: [PlayerGroup]

    @AppStorage("pwaSubmissionsEnabled") private var pwaSubmissionsEnabled = false

    @State private var searchText = ""
    @State private var groupFilter: UUID?
    @State private var linkFilter: LinkFilterV2 = .all
    @State private var showAddPlayerAlert = false
    @State private var newPlayerName = ""
    @State private var pendingRemove: RosterMember?
    /// SEARCH reveals this inline instead of navigating away — it was
    /// always-visible content before; now tucked behind a tap so the
    /// default view is just the roster.
    @State private var showSearch = false
    @State private var importing = false
    @State private var exporting = false
    @State private var importExportMessage: String?
    /// ROSTER's inline accordion panel (see `RosterSettingsViewV2`'s doc
    /// comment) — a single flag, not shared state with anything else on this
    /// screen, so a plain `Bool` rather than an enum like Home's `HomePanel`.
    @State private var showRosterPanel = false

    private var pwaEnabled: Bool { entitlements.canUseCloud && pwaSubmissionsEnabled }

    private var filteredMembers: [RosterMember] {
        members.filter { member in
            (searchText.isEmpty || member.name.localizedCaseInsensitiveContains(searchText))
                && (groupFilter == nil || member.groups.contains { $0.id == groupFilter })
                && (!pwaEnabled || linkFilter == .all
                    || (linkFilter == .active) == (member.submissionTokenRaw != nil))
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                if showSearch {
                    TextField("Search players...", text: $searchText)
                        .textFieldStyle(.plain)
                        .padding(12)
                        .v2FloatingCard()
                }
                filterCard
                if showRosterPanel { rosterPanel }
                playersList
                if let importExportMessage {
                    Text(importExportMessage)
                        .font(.caption)
                        .foregroundStyle(V2Theme.textSecondary)
                        .padding(14)
                        .v2FloatingCard()
                }
                infoCard
            }
            .padding(.horizontal, V2Theme.Spacing.horizontal)
            .padding(.vertical, V2Theme.Spacing.section)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .v2TeamRoomScene()
        .v2FloatingHeaderWithTiles("Players") {
            V2TileGrid {
                V2HomeTile()
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showSearch.toggle() }
                } label: {
                    V2Tile(icon: "magnifyingglass", label: "SEARCH", color: V2Theme.Mode.predictor)
                }
                .buttonStyle(.plain)
                Button { showAddPlayerAlert = true } label: {
                    V2Tile(icon: "plus", label: "ADD", color: V2Theme.accent)
                }
                .buttonStyle(.plain)
            } row2: {
                Button { importing = true } label: {
                    V2Tile(icon: "square.and.arrow.down", label: "IMPORT", color: V2Theme.accent)
                }
                .buttonStyle(.plain)
                Button { exporting = true } label: {
                    V2Tile(icon: "square.and.arrow.up", label: "EXPORT", color: V2Theme.accent)
                }
                .buttonStyle(.plain)
                .disabled(members.isEmpty)
                // Roster moved here from the old dedicated Settings screen —
                // group create/rename/delete, not just the filter pills
                // below (those stay inline; this is management). Expands
                // inline below like Leagues' tiles, not a push.
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showRosterPanel.toggle() }
                } label: {
                    V2Tile(icon: "person.3", label: "ROSTER", color: V2Theme.Mode.lms, isSelected: showRosterPanel)
                }
                .buttonStyle(.plain)
            }
        }
        .alert("Add player", isPresented: $showAddPlayerAlert) {
            TextField("Player name", text: $newPlayerName)
            Button("Add", action: addMember)
                .disabled(trimmedNewName.isEmpty || isDuplicateMember(trimmedNewName))
            Button("Cancel", role: .cancel) { newPlayerName = "" }
        }
        .confirmationDialog(
            "Remove \(pendingRemove?.name ?? "")?",
            isPresented: Binding(get: { pendingRemove != nil }, set: { if !$0 { pendingRemove = nil } }),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let member = pendingRemove {
                    RosterMemberLifecycleService.delete(member, context: context)
                }
                pendingRemove = nil
            }
            Button("Cancel", role: .cancel) { pendingRemove = nil }
        } message: {
            Text("This also deactivates their submission link, if they have one.")
        }
        .fileImporter(
            isPresented: $importing,
            allowedContentTypes: [.commaSeparatedText, .plainText],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
        .fileExporter(
            isPresented: $exporting,
            document: RosterCSVDocument(text: RosterCSV.serialize(members)),
            contentType: .commaSeparatedText,
            defaultFilename: "players"
        ) { result in
            switch result {
            case .success:
                importExportMessage = members.count == 1
                    ? AppString("Exported 1 player.")
                    : AppString("Exported \(members.count) players.")
            case .failure(let error):
                importExportMessage = AppString("Export failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: CSV import (see `RosterImporter` — shared with
    // RosterSettingsViewV2.handleImport/importRows. No per-row group picker
    // here, so no fallback group: rows with a group column still resolve
    // to/create that group; rows without one stay ungrouped.)

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            importExportMessage = AppString("Import failed: \(error.localizedDescription)")
        case .success(let urls):
            guard let url = urls.first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let text = try String(contentsOf: url, encoding: .utf8)
                importRows(RosterCSV.parse(text))
            } catch {
                importExportMessage = AppString("Couldn't read file: \(error.localizedDescription)")
            }
        }
    }

    private func importRows(_ rows: [RosterCSV.Row]) {
        let summary = RosterImporter.importRows(
            rows, existingMembers: members, existingGroups: groups, context: context
        )

        var parts = [summary.added == 1 ? AppString("Imported 1 new player") : AppString("Imported \(summary.added) new players")]
        if summary.skipped > 0 {
            parts.append(summary.skipped == 1 ? AppString("1 already existed") : AppString("\(summary.skipped) already existed"))
        }
        importExportMessage = parts.joined(separator: ", ") + "."
    }

    @ViewBuilder
    private var filterCard: some View {
        if !groups.isEmpty || pwaEnabled {
            VStack(alignment: .leading, spacing: 12) {
                if !groups.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            SelectablePill(title: "All Groups", isSelected: groupFilter == nil) { groupFilter = nil }
                            ForEach(groups) { group in
                                SelectablePill(title: group.name, isSelected: groupFilter == group.id) {
                                    groupFilter = group.id
                                }
                            }
                        }
                    }
                }
                if pwaEnabled {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(LinkFilterV2.allCases) { filter in
                                SelectablePill(title: filter.label, isSelected: linkFilter == filter) {
                                    linkFilter = filter
                                }
                            }
                        }
                    }
                }
            }
            .padding(14)
            .v2FloatingCard()
        }
    }

    /// ROSTER's inline panel — `RosterSettingsViewV2` embedded directly (its
    /// own scene/header stripped, see that file's doc comment), height-
    /// bounded so its own `ScrollView` scrolls inside this card instead of
    /// trying to grow to fill the whole screen.
    private var rosterPanel: some View {
        Card(floating: true) {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "Roster")
                RosterSettingsViewV2()
                    .frame(height: V2Theme.Spacing.inlinePanelHeight)
                    .clipShape(RoundedRectangle(cornerRadius: V2Theme.Radius.row, style: .continuous))
            }
        }
    }

    /// Same floating-card language as `GameSummaryRow` on Home/Games — each
    /// player gets its own card over the locker-room photo, not a bare text
    /// row, so this screen reads as part of the same system rather than a
    /// different, more minimal style.
    @ViewBuilder
    private var playersList: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: filteredMembers.count == 1 ? "1 player" : "\(filteredMembers.count) players")
            if members.isEmpty {
                Text("No saved players yet. Add people here, then add them to a game.")
                    .font(.caption).foregroundStyle(V2Theme.textSecondary)
            } else if filteredMembers.isEmpty {
                Text("No players match.")
                    .font(.caption).foregroundStyle(V2Theme.textSecondary)
            } else {
                VStack(spacing: 10) {
                    ForEach(filteredMembers) { member in
                        NavigationLink {
                            PlayerDetailViewV2(member: member, pwaEnabled: pwaEnabled)
                        } label: {
                            playerRow(member)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) {
                                pendingRemove = member
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
    }

    private func playerRow(_ member: RosterMember) -> some View {
        HStack {
            Text(member.name)
                .font(V2Theme.Typography.rowTitle)
                .foregroundStyle(V2Theme.textPrimary)
            Spacer()
            if pwaEnabled {
                Image(systemName: member.submissionTokenRaw != nil ? "link" : "plus.circle")
                    .font(.caption)
                    .foregroundStyle(V2Theme.textSecondary)
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(V2Theme.textSecondary)
        }
        .padding(14)
        .v2FloatingCard()
    }

    private var infoCard: some View {
        Text(pwaEnabled
             ? "Give each player a private link so they can submit picks themselves. You approve before it goes live."
             : "Turn on player links in Settings to share a personal submission link with each player.")
            .font(.caption).foregroundStyle(V2Theme.textSecondary)
            .padding(14)
            .v2FloatingCard()
    }

    private var trimmedNewName: String { newPlayerName.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func isDuplicateMember(_ name: String) -> Bool {
        guard !name.isEmpty else { return false }
        return members.contains { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
    }

    private func addMember() {
        let name = trimmedNewName
        guard !name.isEmpty, !isDuplicateMember(name) else { return }
        context.insert(RosterMember(name: name))
        newPlayerName = ""
    }
}

private enum LinkFilterV2: String, CaseIterable, Identifiable {
    case all, active, none
    var id: String { rawValue }
    var label: String {
        switch self {
        case .all: return AppString("All Players")
        case .active: return AppString("Has Link")
        case .none: return AppString("No Link")
        }
    }
}
