import Combine
import SwiftData
import SwiftUI

/// Enter per-fixture results (or pull them from the server) and close a
/// Killer round. Mirrors LMS's `ResultsEntryView` (outcome-based, same as
/// Killer's own predictions) rather than Predictor's score-based one.
struct KillerResultsEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(Entitlements.self) private var entitlements
    let game: Game
    let round: Round

    @AppStorage("pwaSubmissionsEnabled") private var pwaSubmissionsEnabled = false
    @AppStorage(ManagerSettings.nameKey) private var managerName = ""
    @State private var data: LeagueData?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var outcomes: [Int: FixtureOutcome] = [:]
    @State private var voided: Set<Int> = []
    @State private var refresh = LiveMatchRefreshState()
    @State private var closeError: String?
    @State private var splitMessage: String?
    @State private var showingIncompleteWarning = false
    @State private var pendingSubmissionCount = 0
    @State private var showingPendingSubmissionsWarning = false

    private var roundFixtures: [MatchDTO] {
        guard let data else { return [] }
        let ids = Set(round.fixtureIds)
        return data.matches.filter { ids.contains($0.id) }.sorted(by: MatchDTO.byKickoffThenId)
    }

    private var allResultsSet: Bool {
        !roundFixtures.isEmpty && roundFixtures.allSatisfy { outcomes[$0.id] != nil || voided.contains($0.id) }
    }

    /// Every active player must have a complete slate (predictions, plus a
    /// hit target on each in Kill Phase) before the round can be closed —
    /// otherwise a no-show player would silently score nothing with no
    /// warning. Named players missing a slate are surfaced in the footer.
    private var incompletePlayers: [Player] {
        game.activePlayers.filter { !KillerScoringService.slateComplete(for: $0, round: round, game: game) }
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
            if allResultsSet, !incompletePlayers.isEmpty {
                let names = incompletePlayers.map(\.name).joined(separator: ", ")
                Text("Waiting on: \(names)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button { attemptClose() } label: {
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
        .confirmationDialog(
            "Round not fully settled",
            isPresented: $showingIncompleteWarning,
            titleVisibility: .visible
        ) {
            Button("Close Anyway", role: .destructive) { close() }
            Button("Cancel", role: .cancel) {}
        } message: {
            let names = incompletePlayers.map(\.name).joined(separator: ", ")
            Text("\(names) still \(incompletePlayers.count == 1 ? "hasn't" : "haven't") finished predicting — closing now leaves them scoring nothing this round.")
        }
        .confirmationDialog(
            pendingSubmissionCount == 1
                ? AppString("1 player submission not yet reviewed")
                : AppString("\(pendingSubmissionCount) player submissions not yet reviewed"),
            isPresented: $showingPendingSubmissionsWarning,
            titleVisibility: .visible
        ) {
            Button("Close Anyway", role: .destructive) { checkIncompleteThenClose() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Closing this round leaves them unresolved in the Submission Queue. Review them first, or close anyway.")
        }
        .alert("Split win", isPresented: Binding(
            get: { splitMessage != nil },
            set: { if !$0 { splitMessage = nil } }
        )) {
            Button("OK") { dismiss() }
        } message: {
            Text(splitMessage ?? "")
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

    /// Checks for unreviewed player submissions before falling through to the
    /// incomplete-predictions check, so pending PWA submissions aren't
    /// silently stranded once the round closes (mirrors LMS/Predictor's
    /// ResultsEntryView — issue #9 hadn't been extended to Killer yet).
    /// Skips the check entirely when PWA submissions aren't in use.
    private func attemptClose() {
        guard entitlements.canUseCloud, pwaSubmissionsEnabled, let gameToken = game.cloudGameToken else {
            checkIncompleteThenClose()
            return
        }
        Task {
            let count = (try? await SubmissionsClient.shared.listSubmissions(
                gameToken: gameToken, round: round.roundNumber
            ))?.filter { $0.status == "pending" }.count ?? 0
            await MainActor.run {
                if count > 0 {
                    pendingSubmissionCount = count
                    showingPendingSubmissionsWarning = true
                } else {
                    checkIncompleteThenClose()
                }
            }
        }
    }

    /// Missing predictions are a soft warning, not a hard block — Killer has
    /// no Auto-Assign-style escape hatch for an unresponsive player, so a hard
    /// gate here would let one no-show deadlock the round forever.
    private func checkIncompleteThenClose() {
        if incompletePlayers.isEmpty {
            close()
        } else {
            showingIncompleteWarning = true
        }
    }

    private func close() {
        do {
            let outcome = try KillerScoringService.closeRound(
                round, game: game, finalOutcomes: outcomes, voidFixtureIds: voided, context: context
            )
            try context.save()
            if game.status == .complete {
                // Single-survivor, outright-winner, or auto-split path — the
                // game just ended with no further round to open, so push
                // explicitly rather than relying on the next round-open's
                // piggyback (there is no next round). See `PWARoundPusher`.
                pushGameCompleteIfNeeded()
            }
            if case .split(let ids) = outcome {
                let names = game.players.filter { ids.contains($0.id) }.map(\.name).joined(separator: ", ")
                splitMessage = "Tied on accuracy and hits — the win splits between \(names)."
            } else {
                dismiss()
            }
        } catch {
            closeError = error.localizedDescription
        }
    }

    private func pushGameCompleteIfNeeded() {
        guard entitlements.canUseCloud, pwaSubmissionsEnabled, game.cloudGameToken != nil else { return }
        let name = managerName
        Task { try? await PWARoundPusher.pushKiller(game: game, round: nil, managerName: name, context: context) }
    }
}
