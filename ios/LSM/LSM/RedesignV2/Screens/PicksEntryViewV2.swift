import SwiftUI
import SwiftData

/// Card restyle of `PicksEntryView`. Same logic — per-player eligible-team
/// picker, auto-assign, stale-table prompt — copied rather than shared,
/// matching the rest of this branch. Replaces the searchable `List` with a
/// filter-pill row (matching `PlayersViewV2`'s convention) and a sheet-based
/// team picker restyled from `TeamPickSheet`.
struct PicksEntryViewV2: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let game: Game
    let round: Round

    @State private var data: LeagueData?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showAutoAssignConfirm = false
    @State private var showStaleTablePrompt = false
    @State private var searchText = ""
    @State private var unassignedOnly = false

    private var teamRefs: [TeamRef] {
        guard let data else { return [] }
        return GameLogicService.teamRefs(
            forFixtureIds: round.fixtureIds,
            fixtures: data.matches,
            teamsById: data.teamsById,
            standingsByTeam: data.standingsByTeam
        )
    }

    private var activePlayers: [Player] {
        game.players.filter { $0.status == .active }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var unpickedCount: Int {
        activePlayers.filter { GameLogicService.pick(for: $0, in: round) == nil }.count
    }

    private var filteredPlayers: [Player] {
        activePlayers.filter { player in
            (!unassignedOnly || GameLogicService.pick(for: player, in: round) == nil)
                && (searchText.isEmpty || player.name.localizedCaseInsensitiveContains(searchText))
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: V2Theme.Spacing.section) {
                    if activePlayers.isEmpty {
                        ContentUnavailableView("No active players", systemImage: "person.slash")
                            .padding(.top, 40)
                    } else {
                        filterCard
                        TextField("Search players", text: $searchText)
                            .textFieldStyle(.plain)
                            .padding(12)
                            .v2FloatingCard(cornerRadius: V2Theme.Radius.row)
                        playersCard
                    }
                }
                .padding(.horizontal, V2Theme.Spacing.horizontal)
                .padding(.vertical, V2Theme.Spacing.section)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .v2LMSFormScene()
            .v2LoadingOverlay(isLoading && data == nil, label: "Loading fixtures…")
            .v2FloatingHeader("Picks · Round \(round.roundNumber)") {
                Button("Auto-Assign") { showAutoAssignConfirm = true }
                    .disabled(teamRefs.isEmpty || unpickedCount == 0)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(teamRefs.isEmpty || unpickedCount == 0 ? V2Theme.textTertiary : V2Theme.Mode.lms)
            }
            .task { await load() }
            .safeAreaInset(edge: .top) {
                if game.isDemoData && TutorialManager.shared.isActive {
                    TutorialSheetBanner(
                        title: "Tutorial picks pre-assigned",
                        detail: "Each player's pick is set for the tutorial. Tap Done ↑ to save and continue."
                    )
                }
            }
            .confirmationDialog(
                unpickedCount == 1
                    ? AppString("Auto-assign 1 player?")
                    : AppString("Auto-assign \(unpickedCount) players?"),
                isPresented: $showAutoAssignConfirm,
                titleVisibility: .visible
            ) {
                Button("Auto-Assign") { runAutoAssign() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Each unassigned player gets the bottom-of-table team still available to them.")
            }
            .confirmationDialog(
                AppString("The league table is over an hour old"),
                isPresented: $showStaleTablePrompt,
                titleVisibility: .visible
            ) {
                Button("Fetch latest table") {
                    AdGate.run { Task { await refreshTableThenAssign() } }
                }
                Button("Use current table") { commitAutoAssign() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Auto-assign uses the bottom-of-table team. Fetch the latest table first, or assign on the one you have?")
            }
        }
    }

    private var filterCard: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                SelectablePill(title: "All (\(activePlayers.count))", isSelected: !unassignedOnly, tint: V2Theme.Mode.lms) {
                    unassignedOnly = false
                }
                SelectablePill(title: "Unassigned (\(unpickedCount))", isSelected: unassignedOnly, tint: V2Theme.Mode.lms) {
                    unassignedOnly = true
                }
            }
        }
    }

    private var playersCard: some View {
        Card(floating: true) {
            VStack(alignment: .leading, spacing: 10) {
                if filteredPlayers.isEmpty {
                    Text(unassignedOnly ? "Everyone's assigned." : "No players match.")
                        .font(.footnote).foregroundStyle(V2Theme.textSecondary)
                } else {
                    VStack(spacing: 6) {
                        ForEach(filteredPlayers) { player in
                            PlayerPickRowV2(
                                player: player,
                                round: round,
                                teamRefs: teamRefs,
                                allowRepeats: game.allowRepeats,
                                teamsById: data?.teamsById ?? [:]
                            )
                        }
                    }
                }
            }
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            data = try await LeagueData.load(for: game.leagues)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
        if game.isDemoData { assignTutorialPicks() }
    }

    private func assignTutorialPicks() {
        let picks: [String: Int] = round.roundNumber == 1
            ? TutorialDataGenerator.lmsRound1Picks
            : TutorialDataGenerator.lmsRound2Picks
        for player in game.activePlayers {
            guard GameLogicService.pick(for: player, in: round) == nil,
                  let teamId = picks[player.name] else { continue }
            GameLogicService.setPick(player: player, round: round, teamId: teamId, context: context)
        }
        try? context.save()
    }

    private func runAutoAssign() {
        if let date = data?.standingsDate,
           !LeagueDataCache.isFresh(date, ttl: CacheTTL.autoAssignTableStale) {
            showStaleTablePrompt = true
            return
        }
        commitAutoAssign()
    }

    private func refreshTableThenAssign() async {
        await LeagueData.refreshStandings(for: game.leagues)
        if let fresh = try? await LeagueData.load(for: game.leagues) { data = fresh }
        commitAutoAssign()
    }

    private func commitAutoAssign() {
        let proposals = GameLogicService.proposeAutoAssign(round: round, game: game, teamRefs: teamRefs)
        for proposal in proposals {
            GameLogicService.setPick(
                player: proposal.player, round: round,
                teamId: proposal.team.id, fixtureId: proposal.team.fixtureId,
                context: context
            )
        }
    }
}

private struct PlayerPickRowV2: View {
    @Environment(\.modelContext) private var context
    let player: Player
    let round: Round
    let teamRefs: [TeamRef]
    let allowRepeats: Bool
    let teamsById: [Int: TeamDTO]

    @State private var showPicker = false

    private var eligible: [TeamRef] {
        let standingsKnown = teamRefs.contains { $0.position != nil }
        return GameEngine.orderedAvailableTeams(
            fixtureTeams: teamRefs,
            used: GameLogicService.usedTeamIds(for: player),
            allowRepeats: allowRepeats,
            standingsKnown: standingsKnown
        )
    }

    private var currentPick: Pick? { GameLogicService.pick(for: player, in: round) }

    var body: some View {
        Button {
            showPicker = true
        } label: {
            HStack {
                Text(player.name)
                    .font(V2Theme.Typography.rowTitle)
                    .foregroundStyle(V2Theme.textPrimary)
                Spacer()
                if let currentPick {
                    Text(teamsById[currentPick.teamId]?.shortName ?? "Team \(currentPick.teamId)")
                        .foregroundStyle(V2Theme.textSecondary)
                } else {
                    Text("Assign").foregroundStyle(V2Theme.Mode.lms)
                }
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(V2Theme.textSecondary)
            }
            .padding(10)
            .background(V2Theme.pillBackground, in: RoundedRectangle(cornerRadius: V2Theme.Radius.row, style: .continuous))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showPicker) {
            TeamPickSheetV2(
                playerName: player.name,
                eligible: eligible,
                currentTeamId: currentPick?.teamId,
                currentFixtureId: currentPick?.fixtureId,
                teamsById: teamsById,
                onSelect: { teamId, fixtureId in
                    GameLogicService.setPick(player: player, round: round, teamId: teamId, fixtureId: fixtureId, context: context)
                    showPicker = false
                },
                onClear: currentPick == nil ? nil : {
                    GameLogicService.clearPick(player: player, round: round, context: context)
                    showPicker = false
                }
            )
        }
    }
}

/// Team picker for one player, restyled from `TeamPickSheet` — a team
/// playing twice in the round appears once per fixture, labelled with its
/// opponent so the manager can tell them apart.
private struct TeamPickSheetV2: View {
    @Environment(\.dismiss) private var dismiss
    let playerName: String
    let eligible: [TeamRef]
    let currentTeamId: Int?
    let currentFixtureId: Int?
    let teamsById: [Int: TeamDTO]
    let onSelect: (Int, Int?) -> Void
    let onClear: (() -> Void)?

    private var duplicateTeamIds: Set<Int> {
        var counts: [Int: Int] = [:]
        for team in eligible { counts[team.id, default: 0] += 1 }
        return Set(counts.filter { $0.value > 1 }.keys)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: V2Theme.Spacing.section) {
                    if let onClear {
                        Button(role: .destructive, action: onClear) {
                            HStack {
                                Label("Clear pick", systemImage: "xmark.circle")
                                Spacer()
                            }
                        }
                        .foregroundStyle(V2Theme.danger)
                        .padding(12)
                        .v2FloatingCard(cornerRadius: V2Theme.Radius.row)
                    }
                    Card(floating: true) {
                        VStack(spacing: 6) {
                            ForEach(eligible.sorted { $0.name < $1.name }, id: \.pickKey) { team in
                                Button {
                                    onSelect(team.id, team.fixtureId)
                                } label: {
                                    HStack(spacing: 10) {
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(team.name).foregroundStyle(V2Theme.textPrimary)
                                            if duplicateTeamIds.contains(team.id), let opponentName = team.opponentName {
                                                Text("vs \(opponentName)")
                                                    .font(.caption)
                                                    .foregroundStyle(V2Theme.textSecondary)
                                            }
                                        }
                                        Spacer()
                                        if team.id == currentTeamId && team.fixtureId == currentFixtureId {
                                            Image(systemName: "checkmark").foregroundStyle(V2Theme.Mode.lms)
                                        }
                                    }
                                    .padding(10)
                                    .background(V2Theme.pillBackground, in: RoundedRectangle(cornerRadius: V2Theme.Radius.row, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal, V2Theme.Spacing.horizontal)
                .padding(.vertical, V2Theme.Spacing.section)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .v2LMSFormScene()
            .v2FloatingHeader(playerName, showBack: false) {
                Button("Cancel") { dismiss() }
                    .foregroundStyle(V2Theme.textSecondary)
            }
        }
        .presentationDetents([.medium, .large])
    }
}
