import SwiftUI
import SwiftData

/// Card-based restyle of `PlayersView` — same roster data/filtering, pushed
/// into an existing NavigationStack (no `List`, no embedded NavigationStack).
/// Row tap pushes the unchanged v1 `PlayerDetailView` — link management,
/// renaming, and group editing haven't been restyled yet, matching the
/// "restyle the list, not-yet-restyled detail stays v1" precedent set by
/// `GamesPortalViewV2`.
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
            LazyVStack(spacing: V2Theme.Spacing.section) {
                filterCard
                TextField("Search players...", text: $searchText)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(V2Theme.cardBackground, in: RoundedRectangle(cornerRadius: V2Theme.Radius.row, style: .continuous))
                playersCard
                infoCard
            }
            .padding(.horizontal, V2Theme.Spacing.horizontal)
            .padding(.vertical, V2Theme.Spacing.section)
        }
        .background(V2Theme.background.ignoresSafeArea())
        .v2Header("Players")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAddPlayerAlert = true } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(V2Theme.accent)
                }
                .accessibilityLabel("Add player")
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
    }

    @ViewBuilder
    private var filterCard: some View {
        if !groups.isEmpty || pwaEnabled {
            Card {
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
            }
        }
    }

    @ViewBuilder
    private var playersCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: filteredMembers.count == 1 ? "1 player" : "\(filteredMembers.count) players")
                if members.isEmpty {
                    Text("No saved players yet. Add people here, then add them to a game.")
                        .font(.caption).foregroundStyle(V2Theme.textSecondary)
                } else if filteredMembers.isEmpty {
                    Text("No players match.")
                        .font(.caption).foregroundStyle(V2Theme.textSecondary)
                } else {
                    VStack(spacing: 6) {
                        ForEach(filteredMembers) { member in
                            NavigationLink {
                                PlayerDetailView(member: member, pwaEnabled: pwaEnabled)
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
        .padding(12)
        .background(V2Theme.pillBackground, in: RoundedRectangle(cornerRadius: V2Theme.Radius.row, style: .continuous))
    }

    private var infoCard: some View {
        Card {
            Text(pwaEnabled
                 ? "Give each player a private link so they can submit picks themselves. You approve before it goes live."
                 : "Turn on player links in Settings to share a personal submission link with each player.")
                .font(.caption).foregroundStyle(V2Theme.textSecondary)
        }
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
