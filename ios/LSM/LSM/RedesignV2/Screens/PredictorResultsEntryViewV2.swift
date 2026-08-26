import Combine
import SwiftUI
import SwiftData

/// Card restyle of `PredictorResultsEntryView`. Same logic — live score pull,
/// void, seed-from-cache, close-round warning — copied rather than shared
/// (the original is small enough that duplication is cheap and this keeps
/// v1 completely untouched, matching the rest of this branch).
struct PredictorResultsEntryViewV2: View {
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
    @AppStorage("predictorCloseRoundWarningSuppressed") private var closeWarningSuppressed = false

    private var roundFixtures: [MatchDTO] {
        guard let data else { return [] }
        let ids = Set(round.fixtureIds)
        return data.matches.filter { ids.contains($0.id) }.sorted(by: MatchDTO.byKickoffThenId)
    }

    private var allScoresSet: Bool {
        !roundFixtures.isEmpty && roundFixtures.allSatisfy { scores[$0.id] != nil || voided.contains($0.id) }
    }

    /// Fixtures with a score entered but not yet confirmed final by the
    /// provider — either seeded before full time, or manually keyed in by
    /// the manager while the match is still live/scheduled. Voided fixtures
    /// are excluded. Surfaced in `CloseRoundWarningSheetV2`, never a hard
    /// block, since manual override is sometimes the only way to close a
    /// round the provider never updates.
    private var unfinishedFixtures: [MatchDTO] {
        roundFixtures.filter { fixture in
            scores[fixture.id] != nil && !voided.contains(fixture.id)
                && !fixture.isFinished && !fixture.isPostponedOrCancelled
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
            .v2PredictorFormScene()
            .v2ResultsEntryChrome(
                title: "Results · Round \(round.roundNumber)",
                tint: V2Theme.Mode.predictor,
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
                        title: "Tutorial scores loaded",
                        detail: "Final scores are pre-filled. Tap Close Round ↓ to calculate points."
                    )
                }
            }
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: V2Theme.Spacing.section) {
                Card(floating: true) {
                    VStack(spacing: 10) {
                        ForEach(roundFixtures) { fixture in
                            VStack(alignment: .leading, spacing: 6) {
                                FixtureLabelV2(fixture: fixture, teamsById: data?.teamsById ?? [:])
                                    .foregroundStyle(V2Theme.textPrimary)
                                scoreRow(for: fixture)
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

    @ViewBuilder
    private func scoreRow(for fixture: MatchDTO) -> some View {
        if voided.contains(fixture.id) {
            HStack {
                Text("Voided — no result").font(.subheadline).foregroundStyle(V2Theme.textSecondary)
                Spacer()
                Button { voided.remove(fixture.id) } label: {
                    Image(systemName: "xmark.circle").foregroundStyle(V2Theme.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Un-void fixture")
            }
        } else if scores[fixture.id] != nil {
            HStack {
                scoreField(for: fixture, isHome: true)
                Text("–").foregroundStyle(V2Theme.textTertiary)
                scoreField(for: fixture, isHome: false)
                Spacer()
                Button { scores[fixture.id] = nil } label: {
                    Image(systemName: "xmark.circle").foregroundStyle(V2Theme.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear result")
            }
        } else {
            HStack {
                Button { scores[fixture.id] = (home: 0, away: 0) } label: {
                    Text("Enter result").font(.subheadline).foregroundStyle(V2Theme.Mode.predictor)
                }
                .buttonStyle(.plain)
                Spacer()
                Button { voided.insert(fixture.id) } label: {
                    Text("Void").font(.subheadline).foregroundStyle(V2Theme.textSecondary)
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
            Button { adjust(fixture.id, isHome: isHome, by: -1) } label: { Image(systemName: "minus.circle.fill") }
                .accessibilityLabel("Decrease \(team) score")
            Text("\(value)").font(.body.weight(.bold).monospacedDigit()).frame(width: 20)
                .foregroundStyle(V2Theme.textPrimary)
                .accessibilityLabel("\(team) score: \(value)")
            Button { adjust(fixture.id, isHome: isHome, by: 1) } label: { Image(systemName: "plus.circle.fill") }
                .accessibilityLabel("Increase \(team) score")
        }
        .foregroundStyle(V2Theme.textSecondary)
        .buttonStyle(.plain)
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
            HStack(spacing: 12) {
                Button {
                    PredictorScoringService.saveScores(round, finalScores: scores)
                    try? context.save()
                } label: {
                    Text("Save Scores").frame(maxWidth: .infinity).padding(.vertical, 10)
                }
                .foregroundStyle(V2Theme.textPrimary)
                .background(V2Theme.pillBackground, in: RoundedRectangle(cornerRadius: V2Theme.Radius.button, style: .continuous))
                .opacity(round.status == .closed || scores.isEmpty ? 0.4 : 1)
                .disabled(round.status == .closed || scores.isEmpty)

                Button { attemptClose() } label: {
                    Text("Close Round").frame(maxWidth: .infinity).padding(.vertical, 10)
                }
                .foregroundStyle(V2Theme.accentOnAccent)
                .background(V2Theme.Mode.predictor, in: RoundedRectangle(cornerRadius: V2Theme.Radius.button, style: .continuous))
                .opacity(round.status == .closed || !allScoresSet ? 0.4 : 1)
                .disabled(round.status == .closed || !allScoresSet)
                .tutorialHighlight(when: game.isDemoData && allScoresSet)
            }
            .font(.body.weight(.semibold))
            .padding(.top, 4)
        }
        .padding(.bottom, 6)
        .padding(.horizontal, V2Theme.Spacing.horizontal)
        .background(.ultraThinMaterial)
        .alert("Cannot close round", isPresented: Binding(
            get: { closeError != nil },
            set: { if !$0 { closeError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(closeError ?? "")
        }
        .sheet(isPresented: $showingCloseWarning) {
            CloseRoundWarningSheetV2(
                dontShowAgain: $suppressCloseWarning,
                pendingSubmissionCount: pendingSubmissionCount,
                incompletePlayerNames: PredictorScoringService.incompletePlayers(round: round, game: game).map(\.name),
                unfinishedFixtureCount: unfinishedFixtures.count
            ) {
                if suppressCloseWarning { closeWarningSuppressed = true }
                showingCloseWarning = false
                DispatchQueue.main.async { close() }
            } onCancel: {
                showingCloseWarning = false
            }
            .presentationDetents([.medium])
        }
    }

    private func attemptClose() {
        Task {
            let count = await fetchPendingSubmissionCount()
            await MainActor.run {
                pendingSubmissionCount = count
                let hasIncompletePlayers = !PredictorScoringService.incompletePlayers(round: round, game: game).isEmpty
                if closeWarningSuppressed && count == 0 && !hasIncompletePlayers && unfinishedFixtures.isEmpty {
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

    private func seedScores() {
        for fixture in roundFixtures where scores[fixture.id] == nil && !voided.contains(fixture.id) {
            let saved = round.predictions.first { $0.fixtureId == fixture.id && $0.actualHome != nil }
            if let saved, let h = saved.actualHome, let a = saved.actualAway {
                scores[fixture.id] = (home: h, away: a)
            }
        }
        for fixture in roundFixtures where scores[fixture.id] == nil && !voided.contains(fixture.id) {
            if fixture.isPostponedOrCancelled {
                voided.insert(fixture.id)
            }
        }
        // `homeScore`/`awayScore` tick live during a match, so this must gate
        // on `isFinished` — otherwise an in-progress scoreline gets seeded and
        // treated as final.
        for fixture in roundFixtures where scores[fixture.id] == nil && !voided.contains(fixture.id) {
            if fixture.isFinished, let home = fixture.homeScore, let away = fixture.awayScore {
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

/// Card restyle of `PredictorResultsEntryView`'s private `CloseRoundWarningSheet`.
private struct CloseRoundWarningSheetV2: View {
    @Binding var dontShowAgain: Bool
    let pendingSubmissionCount: Int
    let incompletePlayerNames: [String]
    let unfinishedFixtureCount: Int
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(V2Theme.warning)
                    .padding(.top, 8)

                Text("Check the scores are correct")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(V2Theme.textPrimary)
                    .multilineTextAlignment(.center)

                Text("Closing this round will score every prediction. This can't be changed afterwards, so make sure each result is final and entered correctly.")
                    .font(.subheadline)
                    .foregroundStyle(V2Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                if pendingSubmissionCount > 0 {
                    Text(pendingSubmissionCount == 1
                         ? "1 player submission hasn't been reviewed yet — it will be left unresolved."
                         : "\(pendingSubmissionCount) player submissions haven't been reviewed yet — they will be left unresolved.")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(V2Theme.warning)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !incompletePlayerNames.isEmpty {
                    let names = incompletePlayerNames.joined(separator: ", ")
                    Text("Still to predict: \(names) — closing now scores them nothing this round.")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(V2Theme.warning)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if unfinishedFixtureCount > 0 {
                    Text(unfinishedFixtureCount == 1
                         ? "1 fixture's score hasn't been confirmed full-time by the provider yet."
                         : "\(unfinishedFixtureCount) fixtures' scores haven't been confirmed full-time by the provider yet.")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(V2Theme.warning)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Toggle("Don't show this again", isOn: $dontShowAgain)
                    .font(.subheadline)
                    .tint(V2Theme.Mode.predictor)
                    .disabled(pendingSubmissionCount > 0 || !incompletePlayerNames.isEmpty || unfinishedFixtureCount > 0)

                Spacer(minLength: 0)

                VStack(spacing: 10) {
                    PrimaryButton(title: "Close Round", tint: V2Theme.Mode.predictor, action: onConfirm)
                    Button(role: .cancel, action: onCancel) {
                        Text("Cancel").frame(maxWidth: .infinity).padding(.vertical, 14)
                    }
                    .foregroundStyle(V2Theme.textPrimary)
                    .background(V2Theme.pillBackground, in: RoundedRectangle(cornerRadius: V2Theme.Radius.button, style: .continuous))
                }
            }
            .padding()
            .background(V2Theme.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onCancel) }
            }
        }
    }
}
