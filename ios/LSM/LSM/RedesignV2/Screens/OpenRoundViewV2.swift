import SwiftUI
import SwiftData

/// Card restyle of `OpenRoundView`, shared by Predictor's and LMS's "Open
/// Round" steps. All the same logic — league blending, unplayed/
/// date filters, manual fixtures, deadline, LMS's `strandedPlayers` check
/// (empty for Predictor, which has no "used teams" concept) — copied rather
/// than shared with the original, since that's a large mode-agnostic view
/// also used live by LMS itself; touching it wasn't part of this pass.
/// `AddManualFixtureSheet` is reused as-is (unstyled, out of scope).
///
/// `body`'s scene switch below also branches on `.killer`, but no call site
/// in the app ever constructs this view with a Killer game — Killer's
/// fixed-count Manager Picked Games flow goes entirely through
/// `KillerOpenRoundViewV2` instead (see that file's doc comment). That
/// branch is dead, not reachable-but-untested; left in place rather than
/// removed here since deleting it isn't part of this pass.
struct OpenRoundViewV2: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(Entitlements.self) private var entitlements
    let game: Game
    var roundType: RoundType = .normal
    /// Mode identity color — no default. This screen backs both LMS's "Open
    /// Round" and Predictor's "Open Matchday", and a mode-specific default
    /// here once let a caller silently render one mode's screen in the
    /// other's color — see V2 audit 4.1, where `GameWizardViewV2`'s shared
    /// `.openRound` sheet case did exactly that. Pass
    /// `V2Theme.Mode.color(for: game.mode)` (or the caller's own mode
    /// constant) explicitly every time instead.
    let tint: Color
    var onOpened: () -> Void = {}

    @State private var data: LeagueData?
    @State private var isLoading = false
    @State private var errorMessage: String?

    @AppStorage("pwaSubmissionsEnabled") private var pwaSubmissionsEnabled = false
    @AppStorage(ManagerSettings.nameKey) private var managerName = ""

    @State private var selectedLeagueIds: Set<String> = []
    @State private var unplayedOnly = true
    @State private var dateFilterOn = true
    @State private var dateFrom = Date().addingTimeInterval(-1 * 24 * 3600)
    @State private var dateTo = Date().addingTimeInterval(14 * 24 * 3600)

    @State private var selectedFixtureIds: Set<Int> = []
    @State private var deadline = Date()
    @State private var showAddManualFixture = false

    @State private var cachedEligibleIds: Set<Int> = []
    @State private var cachedHorizonEnd: Date?
    @State private var cachedManualCeiling: Date?

    private var gameLeagues: [LeagueOption] { game.leagues }
    private var isBlended: Bool { gameLeagues.count > 1 }
    private var allFixtures: [MatchDTO] { data?.matches ?? [] }

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

    private var matchesAreStale: Bool {
        guard let date = data?.matchesDate else { return true }
        return !LeagueDataCache.isFresh(date, ttl: CacheTTL.fixturesCourtesyAge)
    }

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

    private func recomputeHorizon() {
        let manualLeagueId = ManualFixtureService.leagueId(for: game)
        let realFixtures = allFixtures.filter { $0.leagueId != manualLeagueId }
        cachedEligibleIds = FixtureHorizon.eligibleFixtureIds(fixtures: realFixtures)
        cachedHorizonEnd = gameLeagues
            .compactMap { FixtureHorizon.horizonEnd(leagueId: $0.id, fixtures: realFixtures) }
            .max()
        cachedManualCeiling = FixtureHorizon.manualFixtureCeiling(realFixtures: realFixtures)
    }

    private var realTeamNames: Set<String> {
        let manualLeagueId = ManualFixtureService.leagueId(for: game)
        guard let data else { return [] }
        return Set(data.teamsById.values.filter { $0.leagueId != manualLeagueId }.map(\.name))
    }

    var body: some View {
        NavigationStack {
            switch game.mode {
            case .lms: scenedBody.v2LMSFormScene()
            case .predictor: scenedBody.v2PredictorFormScene()
            case .killer: scenedBody.v2KillerFormScene()
            }
        }
    }

    private var scenedBody: some View {
        Group {
            if isLoading && data == nil {
                Color.clear.frame(height: 200)
            } else if let errorMessage, data == nil {
                ContentUnavailableView("Couldn't load fixtures", systemImage: "wifi.slash", description: Text(errorMessage))
            } else {
                content
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .v2LoadingOverlay(isLoading, label: "Loading fixtures…")
        .v2FloatingHeader("Open \(roundType.openTitle) \(GameLogicService.nextRoundNumber(for: game))", showBack: false) {
            HStack(spacing: 14) {
                Button("Cancel") { dismiss() }
                    .foregroundStyle(V2Theme.textSecondary)
                Button("Open") { create() }
                    .disabled(selectedFixtureIds.isEmpty || !enoughPlayers || !strandedPlayers.isEmpty)
                    .fontWeight(.semibold)
                    .foregroundStyle(tint)
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

    private var enoughPlayers: Bool { game.activePlayers.count >= 2 }

    private var roundWontReachPlayers: Bool {
        !entitlements.canUseCloud && pwaSubmissionsEnabled && game.cloudGameToken != nil
    }

    private var content: some View {
        ScrollView {
            LazyVStack(spacing: V2Theme.Spacing.section) {
                if !enoughPlayers {
                    warningCard("A game needs at least 2 players to start a round.", icon: "person.2.slash")
                }
                if roundWontReachPlayers {
                    warningCard(
                        "Your subscription has lapsed — this round won't reach the Player App until you resubscribe.",
                        icon: "wifi.exclamationmark"
                    )
                }
                if matchesAreStale {
                    Card(floating: true) {
                        HStack {
                            Label("Fixture list is over 12 hours old", systemImage: "clock.arrow.circlepath")
                                .font(.footnote)
                                .foregroundStyle(V2Theme.textSecondary)
                            Spacer()
                            Button("Refresh") { refreshMatches() }
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(tint)
                        }
                    }
                }

                filtersCard
                fixturesCard

                if !strandedPlayers.isEmpty {
                    Card(floating: true) {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionHeader(title: "No team left to pick")
                            ForEach(strandedPlayers) { player in
                                Label(player.name, systemImage: "exclamationmark.triangle.fill")
                                    .font(.footnote)
                                    .foregroundStyle(V2Theme.warning)
                            }
                            Text("Add more fixtures, or remove one of the ones above, before opening.")
                                .font(.caption).foregroundStyle(V2Theme.textTertiary)
                        }
                    }
                }

                Card(floating: true) {
                    VStack(alignment: .leading, spacing: 8) {
                        MicroLabel(text: "Deadline")
                        DatePicker("Picks due by", selection: $deadline)
                            .foregroundStyle(V2Theme.textPrimary)
                        Text("Defaults to 24 hours before the first selected kick-off — a guide, not a lock.")
                            .font(.caption).foregroundStyle(V2Theme.textTertiary)
                    }
                }
            }
            .padding(.horizontal, V2Theme.Spacing.horizontal)
            .padding(.vertical, V2Theme.Spacing.section)
        }
    }

    private func warningCard(_ text: String, icon: String) -> some View {
        Card(floating: true) {
            Label(text, systemImage: icon)
                .font(.footnote)
                .foregroundStyle(V2Theme.warning)
        }
    }

    private var filtersCard: some View {
        Card(floating: true) {
            VStack(alignment: .leading, spacing: 12) {
                MicroLabel(text: "Filters")
                if isBlended {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(gameLeagues) { league in
                                SelectablePill(
                                    title: league.name,
                                    isSelected: selectedLeagueIds.contains(league.id),
                                    tint: tint
                                ) { toggleLeague(league.id) }
                            }
                        }
                    }
                }
                Toggle("Unplayed only", isOn: $unplayedOnly).tint(tint)
                Toggle("Filter by date", isOn: $dateFilterOn.animation()).tint(tint)
                if dateFilterOn {
                    DatePicker("From", selection: $dateFrom, displayedComponents: .date)
                    DatePicker(
                        "To", selection: $dateTo,
                        in: dateFrom...max(dateFrom, cachedHorizonEnd ?? dateTo),
                        displayedComponents: .date
                    )
                }
                if let cachedHorizonEnd {
                    Text("Fixtures open through \(cachedHorizonEnd.formatted(date: .abbreviated, time: .omitted)).")
                        .font(.caption).foregroundStyle(V2Theme.textTertiary)
                }
            }
            .foregroundStyle(V2Theme.textPrimary)
        }
    }

    private var fixturesCard: some View {
        Card(floating: true) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    MicroLabel(text: "Fixtures (\(selectedFixtureIds.count) selected)")
                    Spacer()
                    if !visibleFixtures.isEmpty {
                        Button(allVisibleSelected ? "Deselect all" : "Select all") { toggleSelectAllVisible() }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(tint)
                    }
                }
                if visibleFixtures.isEmpty {
                    Text("No fixtures match these filters.").font(.footnote).foregroundStyle(V2Theme.textSecondary)
                } else {
                    VStack(spacing: 8) {
                        ForEach(visibleFixtures) { fixture in
                            Button { toggle(fixture.id) } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: selectedFixtureIds.contains(fixture.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selectedFixtureIds.contains(fixture.id) ? tint : V2Theme.textTertiary)
                                    FixtureLabelV2(fixture: fixture, teamsById: data?.teamsById ?? [:])
                                        .foregroundStyle(V2Theme.textPrimary)
                                    if isBlended, let lid = fixture.leagueId, let l = Leagues.lookup(lid) {
                                        Text(l.shortName)
                                            .font(.caption2.weight(.bold))
                                            .foregroundStyle(V2Theme.textSecondary)
                                            .padding(.horizontal, 5).padding(.vertical, 2)
                                            .background(V2Theme.pillBackground, in: Capsule())
                                    }
                                }
                                .padding(10)
                                .background(
                                    selectedFixtureIds.contains(fixture.id) ? V2Theme.highlightBackground : V2Theme.pillBackground,
                                    in: RoundedRectangle(cornerRadius: V2Theme.Radius.row, style: .continuous)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Button { showAddManualFixture = true } label: {
                    Label("Add Manual Fixture", systemImage: "plus.circle")
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(tint)
            }
        }
    }

    private func toggleLeague(_ id: String) {
        if selectedLeagueIds.contains(id) {
            if selectedLeagueIds.count > 1 { selectedLeagueIds.remove(id) }
        } else {
            selectedLeagueIds.insert(id)
        }
    }

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

    private func syncDeadlineToSelection() {
        let kickoffs = allFixtures
            .filter { selectedFixtureIds.contains($0.id) }
            .compactMap { FixtureFormat.kickoffDate($0.kickoff) }
        if let earliest = kickoffs.min() {
            deadline = earliest.addingTimeInterval(-24 * 3600)
        }
    }

    private static func isUnplayed(_ f: MatchDTO) -> Bool {
        f.status != "FINISHED" && f.status != "CANCELLED"
    }

    private func dateInRange(_ f: MatchDTO) -> Bool {
        guard let k = FixtureFormat.kickoffDate(f.kickoff) else { return false }
        let cal = Calendar.current
        return k >= cal.startOfDay(for: dateFrom) && k < cal.startOfDay(for: cal.date(byAdding: .day, value: 1, to: dateTo) ?? dateTo)
    }

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

    private func refreshMatches() {
        AdGate.run {
            Task {
                for league in gameLeagues { _ = try? await LeagueData.pullLiveMatches(for: league) }
                await load()
            }
        }
    }

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
            Task { try? await PWARoundPusher.pushLMSOrPredictor(game: game, round: round, managerName: name, context: context, scope: PWAPlayerScope.forRoundPush(game: game)) }
        }
        onOpened()
        dismiss()
    }
}
