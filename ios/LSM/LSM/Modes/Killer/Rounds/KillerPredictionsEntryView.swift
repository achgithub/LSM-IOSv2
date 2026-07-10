import SwiftUI
import SwiftData

/// Manager-typed Build Phase predictions entry for one round: a Home/Draw/Away
/// guess per Manager Picked Game, shown one player at a time. Mirrors
/// `PredictionsEntryView`'s per-player slate pattern; Kill Phase's additional
/// Hit-target picker lands in Milestone 3 (`KillerHitTargetPickerView`).
struct KillerPredictionsEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let game: Game
    let round: Round

    @State private var data: LeagueData?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedPlayerId: UUID?

    private var activePlayers: [Player] {
        game.players.filter { $0.status == .active }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var roundFixtures: [MatchDTO] {
        guard let data else { return [] }
        let ids = Set(round.fixtureIds)
        return data.matches.filter { ids.contains($0.id) }.sorted(by: MatchDTO.byKickoffThenId)
    }

    private var selectedPlayer: Player? {
        activePlayers.first { $0.id == selectedPlayerId } ?? activePlayers.first
    }

    private func slateComplete(_ player: Player) -> Bool {
        let fixtureIds = Set(roundFixtures.map(\.id))
        let predicted = Set(KillerScoringService.predictions(for: player, in: round).map(\.fixtureId))
        return !fixtureIds.isEmpty && fixtureIds.isSubset(of: predicted)
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && data == nil {
                    ProgressView("Loading fixtures…")
                } else if let errorMessage, data == nil {
                    ContentUnavailableView("Couldn't load fixtures", systemImage: "wifi.slash", description: Text(errorMessage))
                } else if activePlayers.isEmpty {
                    ContentUnavailableView("No active players", systemImage: "person.slash")
                } else if let player = selectedPlayer {
                    List {
                        Section {
                            Picker("Player", selection: Binding(
                                get: { selectedPlayerId ?? player.id },
                                set: { selectedPlayerId = $0 }
                            )) {
                                ForEach(activePlayers) { p in
                                    Text("\(p.name)\(slateComplete(p) ? " ✓" : "")").tag(p.id)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                        Section("Predictions") {
                            ForEach(roundFixtures) { fixture in
                                KillerFixturePredictionRow(
                                    game: game,
                                    player: player,
                                    round: round,
                                    fixture: fixture,
                                    teamsById: data?.teamsById ?? [:],
                                    isKillPhase: KillerScoringService.phase(for: round, game: game) == .kill
                                )
                            }
                        }
                    }
                }
            }
            .navigationTitle("Predictions · Round \(round.roundNumber)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
            .task { await load() }
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
    }
}

private struct KillerFixturePredictionRow: View {
    @Environment(\.modelContext) private var context
    let game: Game
    let player: Player
    let round: Round
    let fixture: MatchDTO
    let teamsById: [Int: TeamDTO]
    let isKillPhase: Bool

    private var existing: KillerPrediction? {
        KillerScoringService.prediction(for: player, fixtureId: fixture.id, in: round)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            FixtureLabel(fixture: fixture, teamsById: teamsById)
            Picker("Prediction", selection: outcomeBinding) {
                Text("—").tag(FixtureOutcome?.none)
                Text("Home").tag(FixtureOutcome?.some(.homeWin))
                Text("Draw").tag(FixtureOutcome?.some(.draw))
                Text("Away").tag(FixtureOutcome?.some(.awayWin))
            }
            .pickerStyle(.segmented)
            if isKillPhase && existing != nil {
                KillerHitTargetPickerView(game: game, player: player, round: round, fixtureId: fixture.id)
            }
        }
    }

    private var outcomeBinding: Binding<FixtureOutcome?> {
        Binding(
            get: { existing?.predictedOutcome },
            set: { newValue in
                guard let newValue else { return }
                KillerScoringService.setPrediction(
                    player: player, round: round, fixtureId: fixture.id, outcome: newValue, context: context
                )
            }
        )
    }
}
