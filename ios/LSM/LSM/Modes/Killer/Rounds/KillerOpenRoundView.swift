import SwiftUI
import SwiftData

/// Open a Killer round: choose exactly N Manager Picked Games, where N is
/// `KillerScoringService.requiredMPGCount(activePlayers:maxMPG:)`. A separate
/// view from the shared `OpenRoundView` rather than a third mode branch on
/// it — Killer's fixed-count constraint is meaningfully different from
/// Predictor's "all fixtures in scope" model, and avoids three-way
/// conditionals in one shared view (see the Killer implementation plan §2).
struct KillerOpenRoundView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let game: Game
    var onOpened: () -> Void = {}

    @State private var data: LeagueData?
    @State private var isLoading = false
    @State private var errorMessage: String?

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
                    form
                }
            }
            .navigationTitle("Open Round \(GameLogicService.nextRoundNumber(for: game))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Open") { create() }
                        .disabled(selectedFixtureIds.count != requiredCount || !enoughPlayers)
                }
            }
            .task { await load() }
        }
    }

    private var form: some View {
        Form {
            if !enoughPlayers {
                Section {
                    Label("A game needs at least 2 players to start a round.",
                          systemImage: "person.2.slash")
                        .foregroundStyle(.orange)
                }
            }

            Section {
                if isBlended {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(gameLeagues) { leaguePill($0) }
                        }
                        .padding(.vertical, 2)
                    }
                    .listRowInsets(EdgeInsets())
                    .padding(.horizontal)
                }
                Toggle("Unplayed only", isOn: $unplayedOnly)
            } header: {
                Text("Filters")
            }

            Section {
                if visibleFixtures.isEmpty {
                    Text("No fixtures match these filters.").foregroundStyle(.secondary)
                } else {
                    ForEach(visibleFixtures) { fixture in
                        Button {
                            toggle(fixture.id)
                        } label: {
                            HStack {
                                Image(systemName: selectedFixtureIds.contains(fixture.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedFixtureIds.contains(fixture.id) ? .green : .secondary)
                                FixtureLabel(fixture: fixture, teamsById: data?.teamsById ?? [:])
                                if isBlended, let lid = fixture.leagueId, let l = Leagues.lookup(lid) {
                                    Text(l.shortName)
                                        .font(.caption2.weight(.bold))
                                        .padding(.horizontal, 5).padding(.vertical, 2)
                                        .background(.tint.opacity(0.15), in: Capsule())
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(!selectedFixtureIds.contains(fixture.id) && selectedFixtureIds.count >= requiredCount)
                    }
                }
            } header: {
                Text("Manager Picked Games (\(selectedFixtureIds.count)/\(requiredCount) selected)")
            } footer: {
                Text("\(game.activePlayers.count) active players → \(requiredCount) MPG this round.")
            }

            Section {
                DatePicker("Predictions due by", selection: $deadline)
            } header: {
                Text("Deadline")
            }
        }
    }

    private func leaguePill(_ league: LeagueOption) -> some View {
        let on = selectedLeagueIds.contains(league.id)
        return Button {
            toggleLeague(league.id)
        } label: {
            Text(league.name)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(on ? Color.accentColor : Color.gray.opacity(0.2), in: Capsule())
                .foregroundStyle(on ? .white : .primary)
        }
        .buttonStyle(.plain)
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
        // Stored kickoff-ordered — this is the numbering the `.fixtures` share
        // card and the scratchpad shorthand both key off, and must match the
        // kickoff-sorted order the predictions/results views independently
        // re-derive (`MatchDTO.byKickoffThenId`).
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
        _ = round
        try? context.save()
        onOpened()
        dismiss()
    }
}
