import Combine
import SwiftData
import SwiftUI

/// Card restyle of `ResultsEntryView` (LMS). Same logic — live score pull,
/// seed-from-cache, close→tie/auto-winner/dismiss branching, pending-PWA-
/// submissions warning — copied rather than shared, matching the rest of
/// this branch. Per-fixture outcome picker restyled as `SelectablePill`s
/// (Home/Draw/Away/Postponed via `FixtureOutcome`), replacing the segmented
/// `Picker` — this is the same shape Killer's V2 results screen will reuse.
struct ResultsEntryViewV2: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(Entitlements.self) private var entitlements
    let game: Game
    let round: Round
    /// Set true when closing leaves everyone eliminated; the parent then
    /// presents the tie resolution (at the top level, after this sheet
    /// dismisses).
    @Binding var pendingResolve: Bool

    @AppStorage("pwaSubmissionsEnabled") private var pwaSubmissionsEnabled = false
    @AppStorage(ManagerSettings.nameKey) private var managerName = ""
    @State private var data: LeagueData?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var outcomes: [Int: FixtureOutcome] = [:]
    @State private var refresh = LiveMatchRefreshState()
    @State private var pendingSubmissionCount = 0
    @State private var showingPendingSubmissionsWarning = false
    @State private var showingUnfinishedFixturesWarning = false
    @State private var closeError: String?

    private var roundFixtures: [MatchDTO] {
        guard let data else { return [] }
        let ids = Set(round.fixtureIds)
        return data.matches.filter { ids.contains($0.id) }.sorted(by: MatchDTO.byKickoffThenId)
    }

    private var allResultsSet: Bool {
        !roundFixtures.isEmpty && roundFixtures.allSatisfy { outcomes[$0.id] != nil }
    }

    /// Fixtures with an outcome entered but not yet confirmed final by the
    /// provider — either seeded before full time, or manually overridden by
    /// the manager. Surfaced as a soft warning before close, never a hard
    /// block, since manual override is sometimes the only way to close a
    /// round the provider never updates (§ round-close gating: never hard-
    /// block on external data).
    private var unfinishedFixtures: [MatchDTO] {
        roundFixtures.filter { fixture in
            outcomes[fixture.id] != nil && !fixture.isFinished && !fixture.isPostponedOrCancelled
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && data == nil {
                    Color.clear.frame(height: 200)
                } else if let errorMessage, data == nil {
                    ContentUnavailableView("Couldn't load fixtures", systemImage: "wifi.slash", description: Text(errorMessage))
                } else {
                    list
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .v2LMSFormScene()
            .v2ResultsEntryChrome(
                title: "Results · Round \(round.roundNumber)",
                tint: V2Theme.Mode.lms,
                isLoading: isLoading,
                leagues: game.leagues,
                refresh: refresh,
                onPullFromServer: pullFromServer,
                onLoad: load
            )
            .safeAreaInset(edge: .bottom) { bottomBar }
            .safeAreaInset(edge: .top) {
                if game.isDemoData && TutorialManager.shared.isActive {
                    TutorialSheetBanner(
                        title: "Tutorial results loaded",
                        detail: "Scores are pre-filled. Tap Close Round ↓ to eliminate and advance."
                    )
                }
            }
            .confirmationDialog(
                pendingSubmissionCount == 1
                    ? AppString("1 player submission not yet reviewed")
                    : AppString("\(pendingSubmissionCount) player submissions not yet reviewed"),
                isPresented: $showingPendingSubmissionsWarning,
                titleVisibility: .visible
            ) {
                Button("Close Anyway", role: .destructive) { close() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Closing this round leaves them unresolved in the Submission Queue. Review them first, or close anyway.")
            }
            .confirmationDialog(
                "Not all fixtures are confirmed full-time",
                isPresented: $showingUnfinishedFixturesWarning,
                titleVisibility: .visible
            ) {
                Button("Close Anyway", role: .destructive) { checkPendingSubmissions() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("At least one result was entered before the provider confirmed the match had finished. Double-check the score before closing.")
            }
            .alert("Cannot close round", isPresented: Binding(
                get: { closeError != nil },
                set: { if !$0 { closeError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(closeError ?? "")
            }
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: V2Theme.Spacing.section) {
                Card(floating: true) {
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
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(FixtureOutcome.allCases) { outcome in
                    SelectablePill(
                        title: outcome.label,
                        isSelected: outcomes[fixture.id] == outcome,
                        tint: V2Theme.Mode.lms
                    ) {
                        outcomes[fixture.id] = outcome
                    }
                }
                if outcomes[fixture.id] != nil {
                    Button { outcomes[fixture.id] = nil } label: {
                        Image(systemName: "xmark.circle").foregroundStyle(V2Theme.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear result")
                }
            }
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 4) {
            if let lastPulled = refresh.lastPulled {
                Text("Updated \(lastPulled.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2).foregroundStyle(V2Theme.textTertiary)
            }
            if refresh.isThrottled, let freshUntil = refresh.freshUntil {
                let remaining = Duration.seconds(max(0, freshUntil.timeIntervalSince(refresh.now)))
                Text("Refresh available in \(remaining.formatted(.time(pattern: .minuteSecond)))")
                    .font(.caption2).foregroundStyle(V2Theme.textTertiary)
            }
            Button { attemptClose() } label: {
                Text("Close Round").frame(maxWidth: .infinity).padding(.vertical, 12)
            }
            .foregroundStyle(V2Theme.accentOnAccent)
            .background(V2Theme.Mode.lms, in: RoundedRectangle(cornerRadius: V2Theme.Radius.button, style: .continuous))
            .opacity(round.status == .closed || !allResultsSet ? 0.4 : 1)
            .disabled(round.status == .closed || !allResultsSet)
            .tutorialHighlight(when: game.isDemoData && allResultsSet)
            .padding(.top, 4)
        }
        .padding(.bottom, 6)
        .padding(.horizontal, V2Theme.Spacing.horizontal)
        .background(.ultraThinMaterial)
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
        for fixture in roundFixtures where outcomes[fixture.id] == nil {
            if fixture.status == "POSTPONED" {
                outcomes[fixture.id] = .postponed
            } else if fixture.isFinished, let outcome = GameLogicService.outcome(fromWinner: fixture.winner) {
                outcomes[fixture.id] = outcome
            }
        }
    }

    private func pullFromServer() async {
        if let fresh = await refresh.pull(for: game.leagues) { data = fresh }
        seedOutcomesFromCache()
    }

    private func attemptClose() {
        guard unfinishedFixtures.isEmpty else {
            showingUnfinishedFixturesWarning = true
            return
        }
        checkPendingSubmissions()
    }

    private func checkPendingSubmissions() {
        guard entitlements.canUseCloud, pwaSubmissionsEnabled, let gameToken = game.cloudGameToken else {
            close()
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
                    close()
                }
            }
        }
    }

    private func close() {
        guard data != nil else { return }
        for fixture in roundFixtures {
            if let outcome = outcomes[fixture.id] {
                GameLogicService.applyResult(
                    fixtureId: fixture.id,
                    homeTeamId: fixture.homeTeamId,
                    awayTeamId: fixture.awayTeamId,
                    outcome: outcome,
                    round: round
                )
            }
        }

        // The UI already gates opening this screen behind every active player
        // having picked (`openRoundPicksComplete`), so `closeRound`'s
        // incomplete-picks guard should never actually trip here. It CAN
        // still trip if a player is added mid-session while this sheet is
        // already open, so this surfaces an alert rather than silently
        // leaving a dead button — no crash, no dropped tap with no feedback.
        let result: RoundCloseResult
        do {
            result = try GameLogicService.closeRound(round, game: game, context: context)
        } catch {
            closeError = error.localizedDescription
            return
        }
        try? context.save()

        if result.allEliminated {
            pendingResolve = true
            dismiss()
        } else if result.remainingActive == 1,
                  let winner = game.players.first(where: { $0.status == .active }) {
            GameLogicService.apply(.winners([winner.id]), game: game)
            try? context.save()
            pushGameCompleteIfNeeded()
            dismiss()
        } else {
            dismiss()
        }
    }

    private func pushGameCompleteIfNeeded() {
        guard entitlements.canUseCloud, pwaSubmissionsEnabled, game.cloudGameToken != nil else { return }
        let name = managerName
        Task { try? await PWARoundPusher.pushLMSOrPredictor(game: game, round: nil, managerName: name, context: context, scope: PWAPlayerScope.forRoundPush(game: game)) }
    }
}
