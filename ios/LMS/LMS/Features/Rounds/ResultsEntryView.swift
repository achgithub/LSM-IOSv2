import SwiftUI
import SwiftData

/// Enter per-fixture results (or pull them from the server) and close the round
/// (§6.5). Closing computes eliminations; if everyone goes out together the tie
/// resolution sheet appears; a single survivor wins automatically.
struct ResultsEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let game: Game
    let round: Round
    /// Set true when closing leaves everyone eliminated; the parent then presents
    /// the tie resolution (at the top level, after this sheet dismisses).
    @Binding var pendingResolve: Bool

    @State private var data: LeagueData?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var outcomes: [Int: FixtureOutcome] = [:]

    private var roundFixtures: [FixtureDTO] {
        guard let data else { return [] }
        let ids = Set(round.fixtureIds)
        return data.fixtures.filter { ids.contains($0.id) }.sorted { $0.kickoff < $1.kickoff }
    }

    /// Every fixture in the round has a result entered — required before closing.
    private var allResultsSet: Bool {
        !roundFixtures.isEmpty && roundFixtures.allSatisfy { outcomes[$0.id] != nil }
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
                    // Free users watch a rewarded ad to pull fresh results;
                    // subscribers pull instantly (see AdGate).
                    Button {
                        AdGate.run { Task { await pullFromServer() } }
                    } label: {
                        Label("Pull results from server", systemImage: "arrow.down.circle")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button { close() } label: {
                    Text("Close Round").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .padding()
                .disabled(round.status == .closed || !allResultsSet)
            }
            .task { await load() }
        }
    }

    private var list: some View {
        List {
            ForEach(roundFixtures) { fixture in
                VStack(alignment: .leading, spacing: 6) {
                    FixtureLabel(fixture: fixture, teamsById: data?.teamsById ?? [:])
                    Picker("Result", selection: outcomeBinding(for: fixture.id)) {
                        Text("—").tag(FixtureOutcome?.none)
                        ForEach(FixtureOutcome.allCases) { Text($0.label).tag(FixtureOutcome?.some($0)) }
                    }
                    .pickerStyle(.menu)
                }
            }
        }
    }

    private func outcomeBinding(for id: Int) -> Binding<FixtureOutcome?> {
        Binding(get: { outcomes[id] }, set: { outcomes[id] = $0 })
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

    private func pullFromServer() async {
        // Re-fetch so the rewarded ad buys genuinely fresh results, not whatever
        // was loaded when the sheet opened. `forceFixtures` bypasses the fixtures
        // TTL — the whole point of this gated action is fresh results. Falls back
        // to current data on failure.
        if let fresh = try? await LeagueData.load(for: game.leagues, forceFixtures: true) { data = fresh }
        for fixture in roundFixtures {
            if fixture.status == "POSTPONED" {
                outcomes[fixture.id] = .postponed
            } else if let outcome = GameLogicService.outcome(fromWinner: fixture.winner) {
                outcomes[fixture.id] = outcome
            }
        }
    }

    private func close() {
        guard data != nil else { return }
        // Apply each entered fixture result to the picks on both teams.
        for fixture in roundFixtures {
            if let outcome = outcomes[fixture.id] {
                GameLogicService.applyResult(
                    homeTeamId: fixture.homeTeamId,
                    awayTeamId: fixture.awayTeamId,
                    outcome: outcome,
                    round: round
                )
            }
        }

        let result = GameLogicService.closeRound(round, game: game, context: context)

        if result.allEliminated {
            // Hand off to the parent to present the resolution at the top level
            // (avoids stacking a sheet on this one).
            pendingResolve = true
            dismiss()
        } else if result.remainingActive == 1,
                  let winner = game.players.first(where: { $0.status == .active }) {
            GameLogicService.apply(.winners([winner.id]), game: game)
            dismiss()
        } else {
            dismiss()
        }
    }
}
