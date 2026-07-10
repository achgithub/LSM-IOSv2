import SwiftUI
import SwiftData

/// Manager-typed predictions entry for one round: a per-player slate, one
/// score per fixture in scope. Mirrors `PicksEntryView`'s loading scaffolding
/// but the unit of entry is a whole slate, not a single team pick — shown one
/// player at a time (a segmented picker) to keep players × fixtures × 2
/// numbers of data entry tolerable without a PWA in Phase 1.
struct PredictionsEntryView: View {
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
        let predicted = Set(PredictorScoringService.predictions(for: player, in: round).map(\.fixtureId))
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
                                FixturePredictionRow(
                                    player: player,
                                    round: round,
                                    fixture: fixture,
                                    teamsById: data?.teamsById ?? [:],
                                    jokerEnabled: game.predictorJokerEnabled
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
            .safeAreaInset(edge: .top) {
                if game.isDemoData && TutorialManager.shared.isActive {
                    TutorialSheetBanner(
                        title: "Enter your prediction",
                        detail: "Other players are pre-filled. Enter a score for the first fixture (try 2–0), then tap Done ↑."
                    )
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
        if game.isDemoData { seedTutorialPredictions() }
    }

    /// Pre-fills all scripted predictions except Alex's fixture 8008, which
    /// the user enters themselves. Alex's other 3 fixtures are pre-filled too.
    private func seedTutorialPredictions() {
        let userFixtureId = TutorialDataGenerator.predictorFirstMatchId
        for player in game.players {
            guard let script = TutorialDataGenerator.predictorScriptedPredictions[player.name] else { continue }
            for fixture in TutorialDataGenerator.predictorFixtures {
                // Leave Alex's first fixture blank for the user to enter
                if player.name == "Alex" && fixture.matchId == userFixtureId { continue }
                // Skip if already set
                let existing = PredictorScoringService.predictions(for: player, in: round)
                if existing.contains(where: { $0.fixtureId == fixture.matchId }) { continue }
                guard let pred = script[fixture.matchId] else { continue }
                PredictorScoringService.setPrediction(
                    player: player, round: round,
                    fixtureId: fixture.matchId, home: pred.home, away: pred.away,
                    context: context
                )
            }
        }
        try? context.save()
    }
}

private struct FixturePredictionRow: View {
    @Environment(\.modelContext) private var context
    let player: Player
    let round: Round
    let fixture: MatchDTO
    let teamsById: [Int: TeamDTO]
    let jokerEnabled: Bool

    private var existing: Prediction? {
        PredictorScoringService.prediction(for: player, fixtureId: fixture.id, in: round)
    }
    private var home: Int { existing?.predictedHome ?? 0 }
    private var away: Int { existing?.predictedAway ?? 0 }
    private var isJoker: Bool { existing?.isJoker ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            FixtureLabel(fixture: fixture, teamsById: teamsById)
            HStack {
                scoreStepper(value: home, idPrefix: "predictionHome-\(fixture.id)") { setScore(home: $0, away: away) }
                Text("–").foregroundStyle(.secondary)
                scoreStepper(value: away, idPrefix: "predictionAway-\(fixture.id)") { setScore(home: home, away: $0) }
                Spacer()
                if jokerEnabled {
                    Button {
                        PredictorScoringService.setJoker(player: player, round: round, fixtureId: fixture.id)
                    } label: {
                        Label("Joker", systemImage: isJoker ? "star.fill" : "star")
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .tint(isJoker ? .yellow : .secondary)
                    .disabled(existing == nil)
                }
            }
        }
    }

    private func scoreStepper(value: Int, idPrefix: String, onChange: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 4) {
            Button { onChange(max(0, value - 1)) } label: { Image(systemName: "minus.circle") }
                .accessibilityIdentifier("\(idPrefix)-minus")
            Text("\(value)").monospacedDigit().frame(width: 20)
            Button { onChange(value + 1) } label: { Image(systemName: "plus.circle") }
                .accessibilityIdentifier("\(idPrefix)-plus")
        }
        .buttonStyle(.plain)
    }

    private func setScore(home: Int, away: Int) {
        PredictorScoringService.setPrediction(
            player: player, round: round, fixtureId: fixture.id, home: home, away: away, context: context
        )
    }
}
