import SwiftUI
import SwiftData

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
    @State private var showRapidEntry = false
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
                infoCard
            }
            .padding(.horizontal, V2Theme.Spacing.horizontal)
            .padding(.top, V2Theme.Spacing.sceneTop)
            .padding(.bottom, V2Theme.Spacing.section)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                // IMPORT/EXPORT tiles removed (V2 simplification pass) — CSV
                // import/export now lives solely in ROSTER's own Import/
                // Export card (it already had the more capable, group-
                // scoped version; having both here and there was two
                // competing paths to the same feature). Freed slots go to
                // RAPID ENTRY, a faster path for the common case of typing
                // names straight in rather than round-tripping a CSV file.
                Button { showRapidEntry = true } label: {
                    V2Tile(icon: "square.and.pencil", label: "RAPID ENTRY", color: V2Theme.accent)
                }
                .buttonStyle(.plain)
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
                V2TileBlank()
            }
        }
        // Applied after the header/fade modifier, not before — the fade
        // mask only ever covers the scrollable content, so the team room
        // photo behind it (this scene's `.background`) stays fully visible
        // the whole way down instead of fading out with it.
        .v2TeamRoomScene()
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
        .fullScreenCover(isPresented: $showRapidEntry) { RapidEntryViewV2() }
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
                                SelectablePill(verbatim: group.name, isSelected: groupFilter == group.id) {
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
                                SelectablePill(verbatim: filter.label, isSelected: linkFilter == filter) {
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
            // Own card background — `SectionHeader`'s text color assumes a
            // card surface (see its doc comment); this was the one header on
            // this screen rendered bare over the locker-room photo instead,
            // which made the count unreadable.
            SectionHeader(title: filteredMembers.count == 1 ? "1 player" : "\(filteredMembers.count) players")
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(V2Theme.cardBackground.opacity(0.9), in: Capsule())
                .overlay(Capsule().stroke(V2Theme.cardBorder.opacity(0.7)))
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
