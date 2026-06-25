import SwiftUI
import SwiftData

/// Enter final scores for a Predictor round's fixtures and close it. Mirrors
/// `ResultsEntryView`'s loading/pull-from-server scaffolding, but seeds the
/// numeric scoreline (`MatchDTO.homeScore`/`awayScore`) rather than a
/// win/draw/loss outcome — the scoring cascade needs actual goals.
struct PredictorResultsEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let game: Game
    let round: Round

    @State private var data: LeagueData?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var scores: [Int: (home: Int, away: Int)] = [:]

    private var roundFixtures: [MatchDTO] {
        guard let data else { return [] }
        let ids = Set(round.fixtureIds)
        return data.matches.filter { ids.contains($0.id) }.sorted(by: MatchDTO.byKickoffThenId)
    }

    private var allScoresSet: Bool {
        !roundFixtures.isEmpty && roundFixtures.allSatisfy { scores[$0.id] != nil }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && data == nil {
                    ProgressView("Loading fixtures…")
                } else if let errorMessage, data == nil {
                    ContentUnavailableView("Couldn't load fixtures", systemImage: "wifi.slash", description: Text(errorMessage))
                } else {
                    list
                }
            }
            .navigationTitle("Results · Round \(round.roundNumber)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) {
                Button { close() } label: {
                    Text("Close Round").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .padding()
                .background(.bar)
                .disabled(round.status == .closed || !allScoresSet)
            }
            .task { await load() }
        }
    }

    private var list: some View {
        List {
            ForEach(roundFixtures) { fixture in
                VStack(alignment: .leading, spacing: 6) {
                    FixtureLabel(fixture: fixture, teamsById: data?.teamsById ?? [:])
                    HStack {
                        scoreField(for: fixture, isHome: true)
                        Text("–").foregroundStyle(.secondary)
                        scoreField(for: fixture, isHome: false)
                    }
                }
            }
        }
    }

    private func scoreField(for fixture: MatchDTO, isHome: Bool) -> some View {
        let current = scores[fixture.id]
        let value = isHome ? (current?.home ?? 0) : (current?.away ?? 0)
        return HStack(spacing: 4) {
            Button { adjust(fixture.id, isHome: isHome, by: -1) } label: { Image(systemName: "minus.circle") }
            Text("\(value)").monospacedDigit().frame(width: 20)
            Button { adjust(fixture.id, isHome: isHome, by: 1) } label: { Image(systemName: "plus.circle") }
        }
        .buttonStyle(.plain)
    }

    private func adjust(_ fixtureId: Int, isHome: Bool, by delta: Int) {
        var current = scores[fixtureId] ?? (home: 0, away: 0)
        if isHome {
            current.home = max(0, current.home + delta)
        } else {
            current.away = max(0, current.away + delta)
        }
        scores[fixtureId] = current
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            data = try await LeagueData.load(for: game.leagues)
        } catch {
            errorMessage = error.localizedDescription
        }
        seedScoresFromCache()
        isLoading = false
    }

    /// Seeds any FINISHED fixture's real scoreline so the manager doesn't
    /// retype results the server already has; manual entry covers the rest.
    private func seedScoresFromCache() {
        for fixture in roundFixtures where scores[fixture.id] == nil {
            if let home = fixture.homeScore, let away = fixture.awayScore {
                scores[fixture.id] = (home: home, away: away)
            }
        }
    }

    private func close() {
        PredictorScoringService.closeRound(round, game: game, finalScores: scores, context: context)
        dismiss()
    }
}
