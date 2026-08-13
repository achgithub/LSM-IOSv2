import SwiftUI
import SwiftData

/// Card restyle of `KillerOpenRoundView`. Choose exactly N Manager Picked
/// Games (`KillerScoringService.requiredMPGCount`) — a fixed-count
/// constraint meaningfully different from `OpenRoundViewV2`'s "all fixtures
/// in scope" model (no manual fixtures, no date filter, no select-all), so
/// this stays its own screen rather than a third mode branch there. Same
/// logic, copied rather than shared.
struct KillerOpenRoundViewV2: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(Entitlements.self) private var entitlements
    let game: Game
    var onOpened: () -> Void = {}

    @State private var data: LeagueData?
    @State private var isLoading = false
    @State private var errorMessage: String?

    @AppStorage("pwaSubmissionsEnabled") private var pwaSubmissionsEnabled = false
    @AppStorage(ManagerSettings.nameKey) private var managerName = ""

    @State private var selectedLeagueIds: Set<String> = []
    @State private var unplayedOnly = true
    @State private var selectedFixtureIds: Set<Int> = []
    @State private var deadline = Date()

    private var gameLeagues: [LeagueOption] { game.leagues }
    private var isBlended: Bool { gameLeagues.count > 1 }
    private var allFixtures: [MatchDTO] { data?.matches ?? [] }

    private var requiredCount: Int {
        KillerScoringService.requiredMPGCount(activePlayers: game.activePlayers.count, maxMPG: game.killerMaxMPG)
    }

    private var visibleFixtures: [MatchDTO] {
        let eligible = FixtureHorizon.eligibleFixtureIds(fixtures: allFixtures)
        return allFixtures.filter { f in
            (f.leagueId.map { selectedLeagueIds.contains($0) } ?? false)
                && (!unplayedOnly || Self.isUnplayed(f))
                && eligible.contains(f.id)
        }
        .sorted { $0.kickoff < $1.kickoff }
    }

    private var enoughPlayers: Bool { game.activePlayers.count >= 2 }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && data == nil {
                    ProgressView("Loading fixtures…")
                } else if let errorMessage, data == nil {
                    ContentUnavailableView("Couldn't load fixtures", systemImage: "wifi.slash", description: Text(errorMessage))
                } else {
                    content
                }
            }
            .background(V2Theme.background.ignoresSafeArea())
            .v2Header("Open Round \(GameLogicService.nextRoundNumber(for: game))")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Open") { create() }
                        .disabled(selectedFixtureIds.count != requiredCount || !enoughPlayers)
                        .foregroundStyle(V2Theme.Mode.killer)
                }
            }
            .task { await load() }
        }
    }

    private var content: some View {
        ScrollView {
            LazyVStack(spacing: V2Theme.Spacing.section) {
                if !enoughPlayers {
                    Card {
                        Label("A game needs at least 2 players to start a round.", systemImage: "person.2.slash")
                            .font(.footnote)
                            .foregroundStyle(V2Theme.warning)
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        MicroLabel(text: "Filters")
                        if isBlended {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(gameLeagues) { league in
                                        SelectablePill(
                                            title: league.name,
                                            isSelected: selectedLeagueIds.contains(league.id),
                                            tint: V2Theme.Mode.killer
                                        ) { toggleLeague(league.id) }
                                    }
                                }
                            }
                        }
                        Toggle("Unplayed only", isOn: $unplayedOnly).tint(V2Theme.Mode.killer)
                    }
                    .foregroundStyle(V2Theme.textPrimary)
                }

                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        MicroLabel(text: "Manager Picked Games (\(selectedFixtureIds.count)/\(requiredCount) selected)")
                        if visibleFixtures.isEmpty {
                            Text("No fixtures match these filters.").font(.footnote).foregroundStyle(V2Theme.textSecondary)
                        } else {
                            VStack(spacing: 8) {
                                ForEach(visibleFixtures) { fixture in
                                    let selected = selectedFixtureIds.contains(fixture.id)
                                    let atCap = !selected && selectedFixtureIds.count >= requiredCount
                                    Button { toggle(fixture.id) } label: {
                                        HStack(spacing: 10) {
                                            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                                .foregroundStyle(selected ? V2Theme.Mode.killer : V2Theme.textTertiary)
                                            FixtureLabelV2(fixture: fixture, teamsById: data?.teamsById ?? [:])
                                                .foregroundStyle(V2Theme.textPrimary)
                                            if isBlended, let lid = fixture.leagueId, let l = Leagues.lookup(lid) {
                                                Text(l.shortName)
                                                    .font(.caption2.weight(.bold))
                                                    .foregroundStyle(V2Theme.textSecondary)
                                                    .padding(.horizontal, 5).padding(.vertical, 2)
                                                    .background(V2Theme.pillBackground, in: Capsule())
                                            }
                                        }
                                        .padding(10)
                                        .background(
                                            selected ? V2Theme.highlightBackground : V2Theme.pillBackground,
                                            in: RoundedRectangle(cornerRadius: V2Theme.Radius.row, style: .continuous)
                                        )
                                        .opacity(atCap ? 0.4 : 1)
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(atCap)
                                }
                            }
                        }
                        Text("\(game.activePlayers.count) active players → \(requiredCount) MPG this round.")
                            .font(.caption).foregroundStyle(V2Theme.textTertiary)
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        MicroLabel(text: "Deadline")
                        DatePicker("Predictions due by", selection: $deadline)
                            .foregroundStyle(V2Theme.textPrimary)
                    }
                }
            }
            .padding(.horizontal, V2Theme.Spacing.horizontal)
            .padding(.vertical, V2Theme.Spacing.section)
        }
    }

    private func toggleLeague(_ id: String) {
        if selectedLeagueIds.contains(id) {
            if selectedLeagueIds.count > 1 { selectedLeagueIds.remove(id) }
        } else {
            selectedLeagueIds.insert(id)
        }
    }

    private func toggle(_ id: Int) {
        if selectedFixtureIds.contains(id) {
            selectedFixtureIds.remove(id)
        } else if selectedFixtureIds.count < requiredCount {
            selectedFixtureIds.insert(id)
        }
        syncDeadlineToSelection()
    }

    private func syncDeadlineToSelection() {
        let kickoffs = allFixtures
            .filter { selectedFixtureIds.contains($0.id) }
            .compactMap { FixtureFormat.kickoffDate($0.kickoff) }
        if let earliest = kickoffs.min() {
            deadline = earliest.addingTimeInterval(-24 * 3600)
        }
    }

    private static func isUnplayed(_ f: MatchDTO) -> Bool {
        f.status != "FINISHED" && f.status != "CANCELLED"
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            data = try await LeagueData.load(for: gameLeagues)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
        if selectedLeagueIds.isEmpty {
            selectedLeagueIds = Set(gameLeagues.map(\.id))
        }
    }

    private func create() {
        let orderedIds = allFixtures
            .filter { selectedFixtureIds.contains($0.id) }
            .sorted { $0.kickoff < $1.kickoff }
            .map(\.id)
        let round = GameLogicService.openRound(
            in: game,
            fixtureIds: orderedIds,
            fixtures: allFixtures,
            deadline: deadline,
            context: context
        )
        try? context.save()
        if entitlements.canUseCloud && pwaSubmissionsEnabled {
            let name = managerName
            Task { try? await PWARoundPusher.pushKiller(game: game, round: round, managerName: name, context: context) }
        }
        onOpened()
        dismiss()
    }
}
