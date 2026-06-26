import Combine
import SwiftData
import SwiftUI

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
    // Shared pull-from-server state — throttle clock is shared with Matches tab
    // (see `LeagueDataCache.sharedMatchesThrottleUntil`): one cooldown for both.
    @State private var refresh = LiveMatchRefreshState()

    private var roundFixtures: [MatchDTO] {
        guard let data else { return [] }
        let ids = Set(round.fixtureIds)
        return data.matches.filter { ids.contains($0.id) }.sorted(by: MatchDTO.byKickoffThenId)
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
                    LiveMatchRefreshButton(state: refresh) { await pullFromServer() }
                }
            }
            .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { tick in
                if refresh.isThrottled { refresh.now = tick }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 4) {
                    if let lastPulled = refresh.lastPulled {
                        Text("Updated \(lastPulled.formatted(date: .omitted, time: .shortened))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if refresh.isThrottled, let freshUntil = refresh.freshUntil {
                        let remaining = Duration.seconds(max(0, freshUntil.timeIntervalSince(refresh.now)))
                        Text("Refresh available in \(remaining.formatted(.time(pattern: .minuteSecond)))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    // Independence / non-affiliation disclaimer, matching Matches.
                    // swiftlint:disable:next line_length
                    Text("Not affiliated with, licensed by or endorsed by any football club, league or federation. An independent tool — team names and fixtures are factual data shown for reference only.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)

                    Button { close() } label: {
                        Text("Close Round").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 8)
                    .disabled(round.status == .closed || !allResultsSet)
                    .tutorialHighlight(when: game.isDemoData && allResultsSet)
                }
                .padding(.bottom, 6)
                .padding(.horizontal)
                .background(.bar)
            }
            .task { await load() }
            .task { refresh.rearm(for: game.leagues) }
            .safeAreaInset(edge: .top) {
                if game.isDemoData && TutorialManager.shared.isActive {
                    TutorialSheetBanner(
                        title: "Tutorial results loaded",
                        detail: "Scores are pre-filled. Tap Close Round ↓ to eliminate and advance."
                    )
                }
            }
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
        seedOutcomesFromCache()
        refresh.rearm(for: game.leagues)
        isLoading = false
    }

    /// Fills in any not-yet-entered outcomes from the currently loaded `data`,
    /// without overwriting outcomes the manager has already set manually.
    private func seedOutcomesFromCache() {
        for fixture in roundFixtures where outcomes[fixture.id] == nil {
            if fixture.status == "POSTPONED" {
                outcomes[fixture.id] = .postponed
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
        try? context.save()

        if result.allEliminated {
            // Hand off to the parent to present the resolution at the top level
            // (avoids stacking a sheet on this one).
            pendingResolve = true
            dismiss()
        } else if result.remainingActive == 1,
                  let winner = game.players.first(where: { $0.status == .active }) {
            GameLogicService.apply(.winners([winner.id]), game: game)
            try? context.save()
            dismiss()
        } else {
            dismiss()
        }
    }
}
