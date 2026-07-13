import Combine
import SwiftUI
import SwiftData

/// Enter final scores for a Predictor round's fixtures, save partial results,
/// and close the round. Mirrors `ResultsEntryView`'s pull-from-server pattern
/// via `LiveMatchRefreshState`, but works with numeric scorelines rather than
/// win/draw/loss outcomes — the scoring cascade needs actual goals.
struct PredictorResultsEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(Entitlements.self) private var entitlements
    let game: Game
    let round: Round

    @AppStorage("pwaSubmissionsEnabled") private var pwaSubmissionsEnabled = false
    @State private var data: LeagueData?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var scores: [Int: (home: Int, away: Int)] = [:]
    @State private var voided: Set<Int> = []
    @State private var refresh = LiveMatchRefreshState()
    @State private var closeError: String?
    @State private var showingCloseWarning = false
    @State private var suppressCloseWarning = false
    @State private var pendingSubmissionCount = 0
    /// Persisted opt-out for the "check your scores" confirmation. Once the
    /// manager ticks "Don't show again" it stays dismissed on this device.
    @AppStorage("predictorCloseRoundWarningSuppressed") private var closeWarningSuppressed = false

    private var roundFixtures: [MatchDTO] {
        guard let data else { return [] }
        let ids = Set(round.fixtureIds)
        return data.matches.filter { ids.contains($0.id) }.sorted(by: MatchDTO.byKickoffThenId)
    }

    private var allScoresSet: Bool {
        !roundFixtures.isEmpty && roundFixtures.allSatisfy { scores[$0.id] != nil || voided.contains($0.id) }
    }

    private static func isPostponedOrCancelled(_ f: MatchDTO) -> Bool {
        f.status == "POSTPONED" || f.status == "CANCELLED"
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
            .safeAreaInset(edge: .top) {
                if game.isDemoData && TutorialManager.shared.isActive {
                    TutorialSheetBanner(
                        title: "Tutorial scores loaded",
                        detail: "Final scores are pre-filled. Tap Close Round ↓ to calculate points."
                    )
                }
            }
            .task { await load() }
            .task { refresh.rearm(for: game.leagues) }
        }
    }

    private var list: some View {
        List {
            ForEach(roundFixtures) { fixture in
                VStack(alignment: .leading, spacing: 6) {
                    FixtureLabel(fixture: fixture, teamsById: data?.teamsById ?? [:])
                    scoreRow(for: fixture)
                }
            }
        }
    }

    @ViewBuilder
    private func scoreRow(for fixture: MatchDTO) -> some View {
        if voided.contains(fixture.id) {
            HStack {
                Text("Voided — no result").foregroundStyle(.secondary).font(.subheadline)
                Spacer()
                Button {
                    voided.remove(fixture.id)
                } label: {
                    Image(systemName: "xmark.circle").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Un-void fixture")
            }
        } else if scores[fixture.id] != nil {
            HStack {
                scoreField(for: fixture, isHome: true)
                Text("–").foregroundStyle(.secondary)
                scoreField(for: fixture, isHome: false)
                Spacer()
                Button {
                    scores[fixture.id] = nil
                } label: {
                    Image(systemName: "xmark.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear result")
            }
        } else {
            HStack {
                Button {
                    scores[fixture.id] = (home: 0, away: 0)
                } label: {
                    Text("Enter result")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                }
                .buttonStyle(.plain)
                Spacer()
                Button {
                    voided.insert(fixture.id)
                } label: {
                    Text("Void")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func scoreField(for fixture: MatchDTO, isHome: Bool) -> some View {
        let current = scores[fixture.id]
        let value = isHome ? (current?.home ?? 0) : (current?.away ?? 0)
        let team = isHome ? AppString("Home") : AppString("Away")
        return HStack(spacing: 4) {
            Button { adjust(fixture.id, isHome: isHome, by: -1) } label: { Image(systemName: "minus.circle") }
                .accessibilityLabel("Decrease \(team) score")
            Text("\(value)").monospacedDigit().frame(width: 20)
                .accessibilityLabel("\(team) score: \(value)")
            Button { adjust(fixture.id, isHome: isHome, by: 1) } label: { Image(systemName: "plus.circle") }
                .accessibilityLabel("Increase \(team) score")
        }
        .buttonStyle(.plain)
    }

    private var bottomBar: some View {
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
            HStack(spacing: 12) {
                Button {
                    PredictorScoringService.saveScores(round, finalScores: scores)
                    try? context.save()
                } label: {
                    Text("Save Scores").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(round.status == .closed || scores.isEmpty)

                Button { attemptClose() } label: {
                    Text("Close Round").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(round.status == .closed || !allScoresSet)
                .tutorialHighlight(when: game.isDemoData && allScoresSet)
            }
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
        .sheet(isPresented: $showingCloseWarning) {
            CloseRoundWarningSheet(
                dontShowAgain: $suppressCloseWarning,
                pendingSubmissionCount: pendingSubmissionCount,
                incompletePlayerNames: PredictorScoringService.incompletePlayers(round: round, game: game).map(\.name)
            ) {
                if suppressCloseWarning { closeWarningSuppressed = true }
                showingCloseWarning = false
                // Let the sheet's dismissal transition finish before dismissing
                // the parent screen — closing both in the same tick stalled
                // SwiftUI's presentation reconciliation long enough to trip the
                // background watchdog (0x8BADF00D) and get the app killed
                // (TestFlight build 28, 2026-07-05).
                DispatchQueue.main.async { close() }
            } onCancel: {
                showingCloseWarning = false
            }
            .presentationDetents([.medium])
        }
    }

    /// Show the "check your scores" confirmation before closing, unless the
    /// manager has previously opted out. Closing writes points and cannot be undone.
    /// Also checks for unreviewed player submissions — that warning can't be
    /// suppressed, since closing would silently strand them either way.
    private func attemptClose() {
        Task {
            let count = await fetchPendingSubmissionCount()
            await MainActor.run {
                pendingSubmissionCount = count
                let hasIncompletePlayers = !PredictorScoringService.incompletePlayers(round: round, game: game).isEmpty
                if closeWarningSuppressed && count == 0 && !hasIncompletePlayers {
                    close()
                } else {
                    suppressCloseWarning = false
                    showingCloseWarning = true
                }
            }
        }
    }

    private func fetchPendingSubmissionCount() async -> Int {
        guard entitlements.canUseCloud, pwaSubmissionsEnabled, let gameToken = game.cloudGameToken else { return 0 }
        let items = try? await SubmissionsClient.shared.listSubmissions(gameToken: gameToken, round: round.roundNumber)
        return items?.filter { $0.status == "pending" }.count ?? 0
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
        seedScores()
        refresh.rearm(for: game.leagues)
        isLoading = false
    }

    private func pullFromServer() async {
        if let fresh = await refresh.pull(for: game.leagues) { data = fresh }
        seedScores()
    }

    /// Seeds scores in priority order: previously-saved actual scores from
    /// predictions first (so partial saves survive), then a postponed/
    /// cancelled status from the API (auto-voided, mirrors how LMS's
    /// `ResultsEntryView` auto-seeds `.postponed`), then FINISHED fixture
    /// scores from the API cache for any that are still undecided.
    private func seedScores() {
        // Restore any scores the manager already saved to predictions.
        for fixture in roundFixtures where scores[fixture.id] == nil && !voided.contains(fixture.id) {
            let saved = round.predictions.first {
                $0.fixtureId == fixture.id && $0.actualHome != nil
            }
            if let saved, let h = saved.actualHome, let a = saved.actualAway {
                scores[fixture.id] = (home: h, away: a)
            }
        }
        // Auto-void postponed/cancelled fixtures rather than leaving them to
        // default to a fabricated scoreline.
        for fixture in roundFixtures where scores[fixture.id] == nil && !voided.contains(fixture.id) {
            if Self.isPostponedOrCancelled(fixture) {
                voided.insert(fixture.id)
            }
        }
        // Fill remaining from the API cache (FINISHED fixtures with known scores).
        for fixture in roundFixtures where scores[fixture.id] == nil && !voided.contains(fixture.id) {
            if let home = fixture.homeScore, let away = fixture.awayScore {
                scores[fixture.id] = (home: home, away: away)
            }
        }
    }

    private func close() {
        do {
            try PredictorScoringService.closeRound(
                round, game: game, finalScores: scores, voidFixtureIds: voided, context: context
            )
            try context.save()
            dismiss()
        } catch {
            closeError = error.localizedDescription
        }
    }
}

/// Confirmation shown before closing a Predictor round. Closing scores every
/// prediction and cannot be undone, so the manager is asked to double-check the
/// scorelines first. A "Don't show again" tick lets experienced managers opt out.
private struct CloseRoundWarningSheet: View {
    @Binding var dontShowAgain: Bool
    let pendingSubmissionCount: Int
    let incompletePlayerNames: [String]
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.orange)
                    .padding(.top, 8)

                Text("Check the scores are correct")
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)

                Text("Closing this round will score every prediction. This can't be changed afterwards, so make sure each result is final and entered correctly.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                if pendingSubmissionCount > 0 {
                    Text(pendingSubmissionCount == 1
                         ? "1 player submission hasn't been reviewed yet — it will be left unresolved."
                         : "\(pendingSubmissionCount) player submissions haven't been reviewed yet — they will be left unresolved.")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !incompletePlayerNames.isEmpty {
                    Text("\(incompletePlayerNames.joined(separator: ", ")) \(incompletePlayerNames.count == 1 ? "hasn't" : "haven't") predicted yet — closing now scores them nothing this round.")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Toggle("Don't show this again", isOn: $dontShowAgain)
                    .font(.subheadline)
                    .disabled(pendingSubmissionCount > 0 || !incompletePlayerNames.isEmpty)

                Spacer(minLength: 0)

                VStack(spacing: 10) {
                    Button(action: onConfirm) {
                        Text("Close Round").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button(role: .cancel, action: onCancel) {
                        Text("Cancel").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onCancel) }
            }
        }
    }
}
