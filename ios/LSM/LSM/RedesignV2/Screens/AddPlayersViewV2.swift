import SwiftUI
import SwiftData

/// Card restyle of `AddPlayersView` — same roster-pull logic (manager
/// add/remove, group filter, search), copied not shared, matching the rest
/// of this branch. Presented as a `.sheet`, so it owns its own
/// `NavigationStack` + `Done` toolbar rather than pushing into a caller's
/// stack (mirrors `NewGameViewV2`'s sheet chrome).
struct AddPlayersViewV2: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @AppStorage(ManagerSettings.nameKey) private var managerName = ""
    @Query(sort: \RosterMember.name) private var roster: [RosterMember]
    @Query(sort: \PlayerGroup.name) private var groups: [PlayerGroup]
    let game: Game

    /// nil = no filter (all roster members).
    @State private var filterGroupId: UUID?
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: V2Theme.Spacing.section) {
                    if !groups.isEmpty {
                        filterCard
                    }
                    TextField("Search players...", text: $searchText)
                        .textFieldStyle(.plain)
                        .padding(12)
                        .v2FloatingCard(cornerRadius: V2Theme.Radius.row)
                    if !managerTrimmed.isEmpty {
                        youCard
                    }
                    addableCard
                    inGameCard
                }
                .padding(.horizontal, V2Theme.Spacing.horizontal)
                .padding(.vertical, V2Theme.Spacing.section)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .v2TrophyRoomScene()
            .v2FloatingHeader("Add Players", showBack: false) {
                Button("Done") { dismiss() }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(V2Theme.textPrimary)
            }
        }
    }

    // MARK: Cards

    private var filterCard: some View {
        Card(floating: true) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    SelectablePill(title: "All players", isSelected: filterGroupId == nil) { filterGroupId = nil }
                    ForEach(groups) { group in
                        SelectablePill(title: group.name, isSelected: filterGroupId == group.id) {
                            filterGroupId = group.id
                        }
                    }
                }
            }
        }
    }

    private var youCard: some View {
        Card(floating: true) {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "You")
                Button {
                    managerInGame ? removeManager() : addManager()
                } label: {
                    HStack {
                        Text("\(managerTrimmed) (you)")
                            .font(V2Theme.Typography.rowTitle)
                            .foregroundStyle(V2Theme.textPrimary)
                        Spacer()
                        Image(systemName: managerInGame ? "minus.circle.fill" : "plus.circle")
                            .foregroundStyle(managerInGame ? V2Theme.danger : V2Theme.accent)
                    }
                    .padding(12)
                    .background(V2Theme.pillBackground, in: RoundedRectangle(cornerRadius: V2Theme.Radius.row, style: .continuous))
                }
                .buttonStyle(.plain)
                Text(managerInGame
                     ? "You're playing — your pick shows on shared cards (⚑)."
                     : "You're not playing this game — no ⚑ on cards.")
                    .font(.caption).foregroundStyle(V2Theme.textSecondary)
            }
        }
    }

    private var addableCard: some View {
        Card(floating: true) {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Add from your players")
                if roster.isEmpty {
                    Text("No saved players yet. Add people on the Players tab first, then add them here.")
                        .font(.caption).foregroundStyle(V2Theme.textSecondary)
                } else if addable.isEmpty {
                    Text(filterGroupId == nil
                         ? "Everyone in your roster is already in this game."
                         : "Everyone in this group is already in this game.")
                        .font(.caption).foregroundStyle(V2Theme.textSecondary)
                } else {
                    Button {
                        for member in addable { add(member) }
                    } label: {
                        Label("Add all (\(addable.count))", systemImage: "person.2.badge.plus")
                            .font(V2Theme.Typography.rowTitle.weight(.semibold))
                            .foregroundStyle(V2Theme.accent)
                    }
                    .buttonStyle(.plain)
                    VStack(spacing: 6) {
                        ForEach(addable) { member in
                            Button {
                                add(member)
                            } label: {
                                HStack {
                                    Text(member.name)
                                        .font(V2Theme.Typography.rowTitle)
                                        .foregroundStyle(V2Theme.textPrimary)
                                    Spacer()
                                    Image(systemName: "plus.circle").foregroundStyle(V2Theme.accent)
                                }
                                .padding(12)
                                .background(V2Theme.pillBackground, in: RoundedRectangle(cornerRadius: V2Theme.Radius.row, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var inGameCard: some View {
        Card(floating: true) {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "In this game (\(game.players.count))")
                if game.players.isEmpty {
                    Text("No players yet.").font(.caption).foregroundStyle(V2Theme.textSecondary)
                } else if filteredInGame.isEmpty {
                    Text("No players match.").font(.caption).foregroundStyle(V2Theme.textSecondary)
                } else {
                    VStack(spacing: 6) {
                        ForEach(filteredInGame) { player in
                            Button {
                                remove(player)
                            } label: {
                                HStack {
                                    Text(player.name)
                                        .font(V2Theme.Typography.rowTitle)
                                        .foregroundStyle(V2Theme.textPrimary)
                                    if player.isManager {
                                        Text("you")
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(V2Theme.accent)
                                    }
                                    Spacer()
                                    Image(systemName: "minus.circle.fill").foregroundStyle(V2Theme.danger)
                                }
                                .padding(12)
                                .background(V2Theme.pillBackground, in: RoundedRectangle(cornerRadius: V2Theme.Radius.row, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    // MARK: Logic (verbatim from AddPlayersView)

    private var sortedPlayers: [Player] {
        game.players.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func existingNames() -> Set<String> {
        Set(game.players.map { $0.name.lowercased() })
    }

    private var managerTrimmed: String { managerName.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var managerInGame: Bool {
        game.players.contains { $0.isManager } ||
        game.players.contains { $0.name.localizedCaseInsensitiveCompare(managerTrimmed) == .orderedSame }
    }

    /// Roster members matching the group filter, not already in the game, and not
    /// the manager (who is added via the dedicated "You" row so the ⚑ is set).
    private var addable: [RosterMember] {
        let inGame = existingNames()
        return roster.filter { member in
            guard !inGame.contains(member.name.lowercased()) else { return false }
            guard member.name.localizedCaseInsensitiveCompare(managerTrimmed) != .orderedSame else { return false }
            guard searchText.isEmpty || member.name.localizedCaseInsensitiveContains(searchText) else { return false }
            guard let filterGroupId else { return true }
            return member.groups.contains { $0.id == filterGroupId }
        }
    }

    /// Players already in the game, after the name search.
    private var filteredInGame: [Player] {
        sortedPlayers.filter { searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    /// Remove a player from this game (cascade deletes their picks).
    private func remove(_ player: Player) {
        KillerScoringService.clearHitTargets(referencing: player, in: game)
        game.players.removeAll { $0.id == player.id }
        context.delete(player)
    }

    private func add(_ member: RosterMember) {
        guard !existingNames().contains(member.name.lowercased()) else { return }
        let player = Player(name: member.name, game: game, entryNumber: game.nextEntryNumber)
        player.rosterMemberId = member.id
        context.insert(player)
        game.players.append(player)
        KillerScoringService.attachStateIfNeeded(to: player, game: game, context: context)

        // If this game already has an open round, the new player needs their
        // own enrollment push — Predictor/Killer round-opens can now omit
        // players[] entirely, so waiting for the next one would leave them
        // unenrolled server-side.
        if member.submissionTokenRaw != nil {
            Task { await PWARoundPusher.pushSinglePlayerIfNeeded(rosterMember: member, context: context) }
        }
    }

    private func addManager() {
        guard !managerTrimmed.isEmpty, !managerInGame else { return }
        let player = Player(name: managerTrimmed, game: game, isManager: true,
                            entryNumber: game.nextEntryNumber)
        context.insert(player)
        game.players.append(player)
        KillerScoringService.attachStateIfNeeded(to: player, game: game, context: context)
    }

    /// Remove the manager from this game (they're running it but not playing).
    private func removeManager() {
        for player in game.players where player.isManager
            || player.name.localizedCaseInsensitiveCompare(managerTrimmed) == .orderedSame {
            KillerScoringService.clearHitTargets(referencing: player, in: game)
            context.delete(player)
        }
    }
}
