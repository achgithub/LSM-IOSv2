import Combine
import SwiftData
import SwiftUI

/// Card restyle of `KillerResultsEntryView`. Same outcome-picker shape
/// `ResultsEntryViewV2` (LMS) established, plus Killer-specific logic
/// preserved verbatim: incomplete-players soft warning (no Auto-Assign
/// escape hatch, so this is never a hard block), the `.split` tied-outcome
/// alert, and the explicit game-complete push (no next round to piggyback
/// on).
struct KillerResultsEntryViewV2: View {
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
    /// Fixtures the manager has manually un-voided — `seedOutcomesFromCache`
    /// must not re-void these just because the source data still shows
    /// POSTPONED, or a deliberate un-void gets silently reverted on the next
    /// refresh.
    @State private var manuallyUnvoided: Set<Int> = []
    @State private var refresh = LiveMatchRefreshState()
    @State private var closeError: String?
    @State private var splitMessage: String?
    @State private var showingIncompleteWarning = false
    @State private var pendingSubmissionCount = 0
    @State private var showingPendingSubmissionsWarning = false
    /// Guards the async gap in `attemptClose()` (awaiting the PWA pending-
    /// submissions check) during which the button would otherwise stay
    /// tappable — a second tap in that window reaches `close()` again before
    /// `round.status` flips, double-scoring predictions and double-applying
    /// Kill Phase Hit damage.
    @State private var isClosing = false

    private var roundFixtures: [MatchDTO] {
        guard let data else { return [] }
        let ids = Set(round.fixtureIds)
        return data.matches.filter { ids.contains($0.id) }.sorted(by: MatchDTO.byKickoffThenId)
    }

    private var allResultsSet: Bool {
        !roundFixtures.isEmpty && roundFixtures.allSatisfy { outcomes[$0.id] != nil || voided.contains($0.id) }
    }

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
            .background(V2Theme.background.ignoresSafeArea())
            .v2Header("Results · Round \(round.roundNumber)")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    LiveMatchRefreshButton(state: refresh) { await pullFromServer() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.foregroundStyle(V2Theme.Mode.killer)
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
        ScrollView {
            LazyVStack(spacing: V2Theme.Spacing.section) {
                Card {
                    VStack(spacing: 14) {
                        ForEach(roundFixtures) { fixture in
                            VStack(alignment: .leading, spacing: 8) {
                                FixtureLabelV2(fixture: fixture, teamsById: data?.teamsById ?? [:])
                                    .foregroundStyle(V2Theme.textPrimary)
                                outcomeRow(for: fixture)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .padding(.horizontal, V2Theme.Spacing.horizontal)
            .padding(.vertical, V2Theme.Spacing.section)
            .padding(.bottom, 60)
        }
    }

    private func outcomeRow(for fixture: MatchDTO) -> some View {
        HStack(spacing: 8) {
            if voided.contains(fixture.id) {
                Text("Voided").font(.subheadline).foregroundStyle(V2Theme.textSecondary)
                Spacer()
                Button("Un-void") { toggleVoid(fixture.id) }
                    .font(.caption.weight(.semibold)).foregroundStyle(V2Theme.textTertiary)
            } else {
                SelectablePill(title: "Home", isSelected: outcomes[fixture.id] == .homeWin, tint: V2Theme.Mode.killer) {
                    outcomes[fixture.id] = .homeWin
                }
                SelectablePill(title: "Draw", isSelected: outcomes[fixture.id] == .draw, tint: V2Theme.Mode.killer) {
                    outcomes[fixture.id] = .draw
                }
                SelectablePill(title: "Away", isSelected: outcomes[fixture.id] == .awayWin, tint: V2Theme.Mode.killer) {
                    outcomes[fixture.id] = .awayWin
                }
                Spacer()
                Button("Void") { toggleVoid(fixture.id) }
                    .font(.caption.weight(.semibold)).foregroundStyle(V2Theme.textTertiary)
            }
        }
    }

    private func toggleVoid(_ id: Int) {
        if voided.contains(id) {
            voided.remove(id)
            manuallyUnvoided.insert(id)
        } else {
            voided.insert(id)
            manuallyUnvoided.remove(id)
            outcomes[id] = nil
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 4) {
            if let lastPulled = refresh.lastPulled {
                Text("Updated \(lastPulled.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2).foregroundStyle(V2Theme.textTertiary)
            }
            if allResultsSet, !incompletePlayers.isEmpty {
                let names = incompletePlayers.map(\.name).joined(separator: ", ")
                Text("Waiting on: \(names)")
                    .font(.caption).foregroundStyle(V2Theme.textTertiary)
            }
            Button { attemptClose() } label: {
                Text("Close Round").frame(maxWidth: .infinity).padding(.vertical, 12)
            }
            .foregroundStyle(V2Theme.accentOnAccent)
            .background(V2Theme.Mode.killer, in: RoundedRectangle(cornerRadius: V2Theme.Radius.button, style: .continuous))
            .opacity(round.status == .closed || !allResultsSet ? 0.4 : 1)
            .disabled(round.status == .closed || !allResultsSet || isClosing)
            .padding(.top, 4)
        }
        .padding(.bottom, 6)
        .padding(.horizontal, V2Theme.Spacing.horizontal)
        .background(V2Theme.background)
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
            Text("Still to predict: \(names) — closing now scores them nothing this round.")
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
                guard !manuallyUnvoided.contains(fixture.id) else { continue }
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

    private func attemptClose() {
        guard entitlements.canUseCloud, pwaSubmissionsEnabled, let gameToken = game.cloudGameToken else {
            checkIncompleteThenClose()
            return
        }
        guard !isClosing else { return }
        isClosing = true
        Task {
            let count = (try? await SubmissionsClient.shared.listSubmissions(
                gameToken: gameToken, round: round.roundNumber
            ))?.filter { $0.status == "pending" }.count ?? 0
            await MainActor.run {
                isClosing = false
                if count > 0 {
                    pendingSubmissionCount = count
                    showingPendingSubmissionsWarning = true
                } else {
                    checkIncompleteThenClose()
                }
            }
        }
    }

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
        Task { try? await PWARoundPusher.pushKiller(game: game, round: nil, managerName: name, context: context, scope: PWAPlayerScope.forRoundPush(game: game)) }
    }
}
