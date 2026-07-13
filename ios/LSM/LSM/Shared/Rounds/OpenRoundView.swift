import SwiftUI
import SwiftData

/// Open a new round: choose a league, narrow fixtures (matchday / date range /
/// unplayed-only) and select the ones the round runs on, then set the picks
/// deadline (spec §6.3). Defaults to upcoming (unplayed) fixtures so managers
/// see selectable games first. Mode-agnostic — instantiated by both LMS's
/// `GameDetailView` and `PredictorGameDetailView`; the only mode-specific
/// branch is `strandedPlayers` (LMS-only "used teams" concept). Also hosts
/// the "Add Manual Fixture" entry point shared by both modes (see
/// `AddManualFixtureSheet`, `ManualFixtureService`).
struct OpenRoundView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(Entitlements.self) private var entitlements
    let game: Game
    /// The kind of round to open. Tie follow-ups pass `.playoff`/`.rollover`.
    var roundType: RoundType = .normal
    /// Called after a round is successfully opened (e.g. to dismiss a parent).
    var onOpened: () -> Void = {}

    @State private var data: LeagueData?
    @State private var isLoading = false
    @State private var errorMessage: String?

    @AppStorage("pwaSubmissionsEnabled") private var pwaSubmissionsEnabled = false
    @AppStorage(ManagerSettings.nameKey) private var managerName = ""

    // Filters — date is the primary driver (matchday numbers don't line up across
    // leagues), so the date window is on by default.
    @State private var selectedLeagueIds: Set<String> = []   // populated with all the game's leagues on load
    @State private var unplayedOnly = true           // default: upcoming fixtures
    @State private var dateFilterOn = true
    @State private var dateFrom = Date().addingTimeInterval(-1 * 24 * 3600)
    @State private var dateTo = Date().addingTimeInterval(14 * 24 * 3600)

    @State private var selectedFixtureIds: Set<Int> = []
    @State private var deadline = Date()
    @State private var showAddManualFixture = false

    // Horizon results cached at load time (see `recomputeHorizon()`) rather
    // than recomputed as plain `var`s on every render. Both depend only on
    // `allFixtures`, not on any selection/filter state, but each involves a
    // full-season ISO8601 parse + per-league sort/cluster pass — cheap once,
    // but SwiftUI re-evaluates plain computed properties on every state
    // change, so left uncached this reran on *every fixture tap* and was
    // the main cause of a visible per-tap stall with a full season loaded
    // (see 2026-07-05 investigation). Recomputing only in `load()` hides the
    // cost behind the "Loading fixtures…" screen instead.
    @State private var cachedEligibleIds: Set<Int> = []
    @State private var cachedHorizonEnd: Date?
    @State private var cachedManualCeiling: Date?

    /// The league(s) this game runs in — fixtures are pooled across them.
    private var gameLeagues: [LeagueOption] { game.leagues }
    private var isBlended: Bool { gameLeagues.count > 1 }

    private var allFixtures: [MatchDTO] { data?.matches ?? [] }

    /// Active players who'd have zero eligible team among the currently
    /// selected fixtures (LMS only — Predictor has no "used teams" concept
    /// to strand anyone with). Without this check the manager could open a
    /// round no team is left for them to pick in; auto-assign and the manual
    /// picker would both come up empty, and the round would close with them
    /// silently un-eliminated.
    private var strandedPlayers: [Player] {
        guard game.mode == .lms, let data else { return [] }
        let refs = GameLogicService.teamRefs(
            forFixtureIds: Array(selectedFixtureIds),
            fixtures: data.matches,
            teamsById: data.teamsById,
            standingsByTeam: data.standingsByTeam
        )
        guard !refs.isEmpty else { return [] }
        return game.activePlayers.filter { player in
            GameEngine.orderedAvailableTeams(
                fixtureTeams: refs,
                used: GameLogicService.usedTeamIds(for: player),
                allowRepeats: false,
                standingsKnown: false
            ).isEmpty
        }
    }

    /// True when the held match data is more than the courtesy threshold old —
    /// shows a "refresh?" nudge rather than silently serving it forever. This
    /// is a courtesy, not a gate of its own: accepting goes through the exact
    /// same Matches ad gate as the Matches tab's refresh button (subscriber →
    /// instant, free → rewarded ad) — there's no separate free path for
    /// fixtures, just a much longer tolerance before bothering to ask.
    private var matchesAreStale: Bool {
        // nil = never fetched at all (e.g. a league switched into for the
        // first time, after the device's one-ever free fill is already
        // spent) — just as worth prompting about as genuinely old data.
        guard let date = data?.matchesDate else { return true }
        return !LeagueDataCache.isFresh(date, ttl: CacheTTL.fixturesCourtesyAge)
    }

    /// Fixtures after every active filter, sorted by kickoff. Manual fixtures
    /// skip the date-range filter — the manager already deliberately chose
    /// its kick-off when adding it by hand, so a filter tuned for the real
    /// schedule shouldn't be able to hide it again — but they're still capped
    /// by the horizon's ceiling (`cachedManualCeiling`), same as the actual
    /// admission check in `GameLogicService.openRound`. Without this, a
    /// manual fixture dated implausibly far out would show as selectable here
    /// only to be silently dropped from the round on Open (issue #15).
    private var visibleFixtures: [MatchDTO] {
        let manualLeagueId = ManualFixtureService.leagueId(for: game)
        return allFixtures.filter { f in
            (f.leagueId.map { selectedLeagueIds.contains($0) } ?? false)
                && (!unplayedOnly || Self.isUnplayed(f))
                && (f.leagueId == manualLeagueId
                    ? manualFixtureWithinCeiling(f)
                    : (cachedEligibleIds.contains(f.id) && (!dateFilterOn || dateInRange(f))))
        }
        .sorted { $0.kickoff < $1.kickoff }
    }

    private func manualFixtureWithinCeiling(_ f: MatchDTO) -> Bool {
        guard let ceiling = cachedManualCeiling, let kickoff = FixtureFormat.kickoffDate(f.kickoff) else { return true }
        return kickoff <= ceiling
    }

    /// Recomputes `cachedEligibleIds`/`cachedHorizonEnd` from the current
    /// `allFixtures` — called only from `load()`, so the cost (a full-season
    /// ISO8601 parse + sort/cluster pass per league) happens once behind the
    /// "Loading fixtures…" screen rather than on every fixture-selection tap.
    /// Both depend only on the fixture data, not on any filter/selection
    /// state, so nothing is lost by not recomputing in between loads.
    private func recomputeHorizon() {
        let manualLeagueId = ManualFixtureService.leagueId(for: game)
        let realFixtures = allFixtures.filter { $0.leagueId != manualLeagueId }
        cachedEligibleIds = FixtureHorizon.eligibleFixtureIds(fixtures: realFixtures)
        cachedHorizonEnd = gameLeagues
            .compactMap { FixtureHorizon.horizonEnd(leagueId: $0.id, fixtures: realFixtures) }
            .max()
        cachedManualCeiling = FixtureHorizon.manualFixtureCeiling(realFixtures: realFixtures)
    }

    /// Names of every real (non-manual) team already loaded for this game's
    /// league(s) — passed to the manual-fixture sheet so it can block an
    /// obvious duplicate up front (see `ManualFixtureService.reconcile` for
    /// the ongoing safety net if a real team is added/renamed to match later).
    private var realTeamNames: Set<String> {
        let manualLeagueId = ManualFixtureService.leagueId(for: game)
        guard let data else { return [] }
        return Set(data.teamsById.values.filter { $0.leagueId != manualLeagueId }.map(\.name))
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && data == nil {
                    ProgressView("Loading fixtures…")
                } else if let errorMessage, data == nil {
                    ContentUnavailableView("Couldn't load fixtures", systemImage: "wifi.slash", description: Text(errorMessage))
                } else {
                    form
                }
            }
            .navigationTitle("Open \(roundType.openTitle) \(GameLogicService.nextRoundNumber(for: game))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Open") { create() }
                        .disabled(selectedFixtureIds.isEmpty || !enoughPlayers || !strandedPlayers.isEmpty)
                }
            }
            .task { await load() }
            .safeAreaInset(edge: .top) {
                if game.isDemoData && TutorialManager.shared.isActive {
                    TutorialSheetBanner(
                        title: "Tutorial fixtures loaded",
                        detail: "All fixtures are pre-selected. Tap Open ↑ to continue."
                    )
                }
            }
            .sheet(isPresented: $showAddManualFixture) {
                AddManualFixtureSheet(
                    game: game,
                    realTeamNames: realTeamNames,
                    existingManualTeams: ManualFixtureService.manualTeams(for: game)
                ) { home, away, kickoff in
                    addManualFixture(home: home, away: away, kickoff: kickoff)
                }
            }
        }
    }

    /// A round needs at least two active players — otherwise there's no contest
    /// and a single player could be "eliminated" into a nonsensical one-way tie.
    private var enoughPlayers: Bool { game.activePlayers.count >= 2 }

    /// True when this game already has PWA in use, but the manager's current
    /// tier means this round's push will be silently skipped by `create()` —
    /// surfaced here instead of leaving it silent (issue #18). Deliberately
    /// still blocked, not grace-windowed like Restore/the Submission Queue:
    /// pushing a NEW round is the ongoing paid service itself, not access to
    /// data that already exists, so there's no free-continuation case to make.
    private var roundWontReachPlayers: Bool {
        !entitlements.canUseCloud && pwaSubmissionsEnabled && game.cloudGameToken != nil
    }

    private var form: some View {
        Form {
            if !enoughPlayers {
                Section {
                    Label("A game needs at least 2 players to start a round.",
                          systemImage: "person.2.slash")
                        .foregroundStyle(.orange)
                }
            }

            if roundWontReachPlayers {
                Section {
                    Label(
                        "Your subscription has lapsed — this round won't reach the Player App until you resubscribe. Players won't be notified and can't submit through their links for it.",
                        systemImage: "wifi.exclamationmark"
                    )
                    .foregroundStyle(.orange)
                }
            }

            // Courtesy, not a gate — accepting still goes through the same
            // Matches ad gate as the Matches tab (instant for subscribers, one
            // ad for free users); this just decides when it's even worth
            // asking. Declining proceeds with whatever's held, however stale.
            if matchesAreStale {
                Section {
                    Label("This fixture list is over 12 hours old — refresh?", systemImage: "clock.arrow.circlepath")
                        .foregroundStyle(.secondary)
                    Button("Refresh fixtures") { refreshMatches() }
                }
            }

            Section {
                // Only show the league control when there's an actual choice — a
                // single-league game uses that league silently (matches New Game).
                if isBlended {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(gameLeagues) { leaguePill($0) }
                        }
                        .padding(.vertical, 2)
                    }
                    .listRowInsets(EdgeInsets())
                    .padding(.horizontal)
                }
                Toggle("Unplayed only", isOn: $unplayedOnly)
                Toggle("Filter by date", isOn: $dateFilterOn.animation())
                if dateFilterOn {
                    DatePicker("From", selection: $dateFrom, displayedComponents: .date)
                    DatePicker(
                        "To", selection: $dateTo,
                        in: dateFrom...max(dateFrom, cachedHorizonEnd ?? dateTo),
                        displayedComponents: .date
                    )
                }
            } header: {
                Text("Filters")
            } footer: {
                if let cachedHorizonEnd {
                    Text("Fixtures open through \(cachedHorizonEnd.formatted(date: .abbreviated, time: .omitted)) — later matchdays open closer to kick-off.")
                }
            }

            Section {
                if visibleFixtures.isEmpty {
                    Text("No fixtures match these filters.").foregroundStyle(.secondary)
                } else {
                    ForEach(visibleFixtures) { fixture in
                        Button {
                            toggle(fixture.id)
                        } label: {
                            HStack {
                                Image(systemName: selectedFixtureIds.contains(fixture.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedFixtureIds.contains(fixture.id) ? .green : .secondary)
                                FixtureLabel(fixture: fixture, teamsById: data?.teamsById ?? [:])
                                if isBlended, let lid = fixture.leagueId, let l = Leagues.lookup(lid) {
                                    Text(l.shortName)
                                        .font(.caption2.weight(.bold))
                                        .padding(.horizontal, 5).padding(.vertical, 2)
                                        .background(.tint.opacity(0.15), in: Capsule())
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                Button {
                    showAddManualFixture = true
                } label: {
                    Label("Add Manual Fixture", systemImage: "plus.circle")
                }
            } header: {
                HStack {
                    Text("Fixtures (\(selectedFixtureIds.count) selected)")
                    Spacer()
                    if !visibleFixtures.isEmpty {
                        Button(allVisibleSelected ? "Deselect all" : "Select all") {
                            toggleSelectAllVisible()
                        }
                        .font(.caption.weight(.semibold))
                        .textCase(nil)
                    }
                }
            }

            if !strandedPlayers.isEmpty {
                Section {
                    ForEach(strandedPlayers) { player in
                        Label(player.name, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                } header: {
                    Text("No team left to pick")
                } footer: {
                    Text("These players have already used every team in the selected fixtures. Add more fixtures, or remove one of the ones above, before opening.")
                }
            }

            Section {
                DatePicker("Picks due by", selection: $deadline)
            } header: {
                Text("Deadline")
            } footer: {
                Text("Defaults to 24 hours before the first selected kick-off. A guide for the manager — picks aren't locked automatically.")
            }
        }
    }

    // MARK: League pills

    private func leaguePill(_ league: LeagueOption) -> some View {
        let on = selectedLeagueIds.contains(league.id)
        return Button {
            toggleLeague(league.id)
        } label: {
            Text(league.name)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(on ? Color.accentColor : Color.gray.opacity(0.2), in: Capsule())
                .foregroundStyle(on ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    private func toggleLeague(_ id: String) {
        if selectedLeagueIds.contains(id) {
            if selectedLeagueIds.count > 1 { selectedLeagueIds.remove(id) }   // keep at least one
        } else {
            selectedLeagueIds.insert(id)
        }
    }

    // MARK: Selection

    private var allVisibleSelected: Bool {
        !visibleFixtures.isEmpty && visibleFixtures.allSatisfy { selectedFixtureIds.contains($0.id) }
    }

    private func toggle(_ id: Int) {
        if selectedFixtureIds.contains(id) { selectedFixtureIds.remove(id) } else { selectedFixtureIds.insert(id) }
        syncDeadlineToSelection()
    }

    private func toggleSelectAllVisible() {
        if allVisibleSelected {
            visibleFixtures.forEach { selectedFixtureIds.remove($0.id) }
        } else {
            visibleFixtures.forEach { selectedFixtureIds.insert($0.id) }
        }
        syncDeadlineToSelection()
    }

    /// Default the deadline to 24 hours before the earliest selected kick-off
    /// (info only — the manager can change it; nothing is enforced).
    private func syncDeadlineToSelection() {
        let kickoffs = allFixtures
            .filter { selectedFixtureIds.contains($0.id) }
            .compactMap { FixtureFormat.kickoffDate($0.kickoff) }
        if let earliest = kickoffs.min() {
            deadline = earliest.addingTimeInterval(-24 * 3600)
        }
    }

    // MARK: Filtering helpers

    private static func isUnplayed(_ f: MatchDTO) -> Bool {
        f.status != "FINISHED" && f.status != "CANCELLED"
    }

    private func dateInRange(_ f: MatchDTO) -> Bool {
        guard let k = FixtureFormat.kickoffDate(f.kickoff) else { return false }
        let cal = Calendar.current
        return k >= cal.startOfDay(for: dateFrom) && k < cal.startOfDay(for: cal.date(byAdding: .day, value: 1, to: dateTo) ?? dateTo)
    }

    // MARK: Load

    private func load() async {
        isLoading = true
        errorMessage = nil
        let isFirstLoad = data == nil
        do {
            let fresh = try await LeagueData.load(for: gameLeagues)
            data = fresh
        } catch {
            errorMessage = error.localizedDescription
        }
        recomputeHorizon()
        isLoading = false
        if selectedLeagueIds.isEmpty {
            selectedLeagueIds = Set(gameLeagues.map(\.id))
        }
        // Default the "To" filter to the horizon boundary rather than a fixed
        // +14 days — only on the very first load, so a manager's own edit
        // (or a later refresh) doesn't get silently overwritten.
        if isFirstLoad, let cachedHorizonEnd {
            dateTo = cachedHorizonEnd
        }
        if game.isDemoData { setupForTutorial() }
    }

    private func setupForTutorial() {
        unplayedOnly = false
        dateFilterOn = false
        let closedCount = game.rounds.filter { $0.status == .closed }.count
        let fixtures: [TutorialDataGenerator.ScriptedFixture]
        if game.mode == .predictor {
            fixtures = TutorialDataGenerator.predictorFixtures
        } else {
            fixtures = closedCount == 0
                ? TutorialDataGenerator.lmsRound1Fixtures
                : TutorialDataGenerator.lmsRound2Fixtures
        }
        selectedFixtureIds = Set(fixtures.map(\.matchId))
    }

    /// The Fixtures-view courtesy prompt's "yes" action — goes through the
    /// exact same ad gate as the Matches tab's refresh (subscriber → instant,
    /// free → rewarded ad), then reloads from the now-fresh cache.
    private func refreshMatches() {
        AdGate.run {
            Task {
                for league in gameLeagues { _ = try? await LeagueData.pullLiveMatches(for: league) }
                await load()
            }
        }
    }

    /// Commits a manually-typed fixture, folds its synthetic league into the
    /// current filter/selection state, and reloads so it appears immediately.
    private func addManualFixture(home: TeamDTO, away: TeamDTO, kickoff: Date) {
        let match = ManualFixtureService.addFixture(homeTeam: home, awayTeam: away, kickoff: kickoff, for: game)
        try? context.save()
        selectedFixtureIds.insert(match.id)
        if let leagueId = match.leagueId { selectedLeagueIds.insert(leagueId) }
        Task { await load() }
    }

    private func create() {
        let round = GameLogicService.openRound(
            in: game,
            fixtureIds: Array(selectedFixtureIds),
            fixtures: allFixtures,
            deadline: deadline,
            roundType: roundType,
            context: context
        )
        try? context.save()
        if entitlements.canUseCloud && pwaSubmissionsEnabled {
            let name = managerName
            Task { try? await PWARoundPusher.pushLMSOrPredictor(game: game, round: round, managerName: name, context: context) }
        }
        onOpened()
        dismiss()
    }
}
