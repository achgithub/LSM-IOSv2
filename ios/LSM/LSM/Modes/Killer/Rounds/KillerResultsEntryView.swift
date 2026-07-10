import Combine
import SwiftData
import SwiftUI

/// Enter per-fixture results (or pull them from the server) and close a
/// Killer round. Mirrors LMS's `ResultsEntryView` (outcome-based, same as
/// Killer's own predictions) rather than Predictor's score-based one.
struct KillerResultsEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let game: Game
    let round: Round
    /// Set when closing produces a `.stillTied` outcome; the parent presents
    /// `KillerTiebreakView` at the top level once this sheet dismisses.
    @Binding var pendingTiebreakIds: [UUID]?

    @State private var data: LeagueData?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var outcomes: [Int: FixtureOutcome] = [:]
    @State private var voided: Set<Int> = []
    @State private var refresh = LiveMatchRefreshState()
    @State private var closeError: String?

    private var roundFixtures: [MatchDTO] {
        guard let data else { return [] }
        let ids = Set(round.fixtureIds)
        return data.matches.filter { ids.contains($0.id) }.sorted(by: MatchDTO.byKickoffThenId)
    }

    private var allResultsSet: Bool {
        !roundFixtures.isEmpty && roundFixtures.allSatisfy { outcomes[$0.id] != nil || voided.contains($0.id) }
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
                ToolbarItem(placement: .primaryAction) {
                    LiveMatchRefreshButton(state: refresh) { await pullFromServer() }
                }
            }
            .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { tick in
                if refresh.isThrottled { refresh.now = tick }
            }
            .safeAreaInset(edge: .bottom) { bottomBar }
            .task { await load() }
            .task { refresh.rearm(for: game.leagues) }
        }
    }

    private var list: some View {
        List {
            ForEach(roundFixtures) { fixture in
                VStack(alignment: .leading, spacing: 6) {
                    FixtureLabel(fixture: fixture, teamsById: data?.teamsById ?? [:])
                    HStack {
                        Picker("Result", selection: outcomeBinding(for: fixture.id)) {
                            Text("—").tag(FixtureOutcome?.none)
                            Text("Home").tag(FixtureOutcome?.some(.homeWin))
                            Text("Draw").tag(FixtureOutcome?.some(.draw))
                            Text("Away").tag(FixtureOutcome?.some(.awayWin))
                        }
                        .pickerStyle(.segmented)
                        .disabled(voided.contains(fixture.id))
                        Button {
                            toggleVoid(fixture.id)
                        } label: {
                            Text(voided.contains(fixture.id) ? "Voided" : "Void")
                        }
                        .font(.caption)
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    private func outcomeBinding(for id: Int) -> Binding<FixtureOutcome?> {
        Binding(get: { outcomes[id] }, set: { outcomes[id] = $0 })
    }

    private func toggleVoid(_ id: Int) {
        if voided.contains(id) {
            voided.remove(id)
        } else {
            voided.insert(id)
            outcomes[id] = nil
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 4) {
            if let lastPulled = refresh.lastPulled {
                Text("Updated \(lastPulled.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Button { close() } label: {
                Text("Close Round").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(round.status == .closed || !allResultsSet)
            .padding(.top, 4)
        }
        .padding(.bottom, 6)
        .padding(.horizontal)
        .background(.bar)
        .alert("Cannot close round", isPresented: Binding(
            get: { closeError != nil },
            set: { if !$0 { closeError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(closeError ?? "")
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
        seedOutcomesFromCache()
        refresh.rearm(for: game.leagues)
        isLoading = false
    }

    private func seedOutcomesFromCache() {
        for fixture in roundFixtures where outcomes[fixture.id] == nil && !voided.contains(fixture.id) {
            if fixture.status == "POSTPONED" {
                voided.insert(fixture.id)
            } else if let outcome = GameLogicService.outcome(fromWinner: fixture.winner) {
                outcomes[fixture.id] = outcome
            }
        }
    }

    private func pullFromServer() async {
        if let fresh = await refresh.pull(for: game.leagues) { data = fresh }
        seedOutcomesFromCache()
    }

    private func close() {
        do {
            let outcome = try KillerScoringService.closeRound(
                round, game: game, finalOutcomes: outcomes, voidFixtureIds: voided, context: context
            )
            try context.save()
            if case .stillTied(let ids) = outcome {
                pendingTiebreakIds = ids
            }
            dismiss()
        } catch {
            closeError = error.localizedDescription
        }
    }
}
