import SwiftUI
import SwiftData
import OSLog

private let submissionsLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "lsm", category: "submissions")

/// Open a new round: choose a league, narrow fixtures (matchday / date range /
/// unplayed-only) and select the ones the round runs on, then set the picks
/// deadline (spec §6.3). Defaults to upcoming (unplayed) fixtures so managers
/// see selectable games first.
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

    /// Fixtures after every active filter, sorted by kickoff.
    private var visibleFixtures: [MatchDTO] {
        allFixtures.filter { f in
            (f.leagueId.map { selectedLeagueIds.contains($0) } ?? false)
                && (!unplayedOnly || Self.isUnplayed(f))
                && (!dateFilterOn || dateInRange(f))
        }
        .sorted { $0.kickoff < $1.kickoff }
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
        }
    }

    /// A round needs at least two active players — otherwise there's no contest
    /// and a single player could be "eliminated" into a nonsensical one-way tie.
    private var enoughPlayers: Bool { game.activePlayers.count >= 2 }

    private var form: some View {
        Form {
            if !enoughPlayers {
                Section {
                    Label("A game needs at least 2 players to start a round.",
                          systemImage: "person.2.slash")
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

            Section("Filters") {
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
                    DatePicker("To", selection: $dateTo, in: dateFrom..., displayedComponents: .date)
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
                                if isBlended, let lid = fixture.leagueId, let l = Leagues.byId(lid) {
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
        do {
            let fresh = try await LeagueData.load(for: gameLeagues)
            data = fresh
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
        if selectedLeagueIds.isEmpty {
            selectedLeagueIds = Set(gameLeagues.map(\.id))
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

    private func create() {
        let round = GameLogicService.openRound(
            in: game,
            fixtureIds: Array(selectedFixtureIds),
            deadline: deadline,
            roundType: roundType,
            context: context
        )
        try? context.save()
        if entitlements.canUseCloud && pwaSubmissionsEnabled {
            pushRound(round)
        }
        onOpened()
        dismiss()
    }

    /// Fire-and-forget round push to the Worker. Mints cloudGameToken on first push.
    private func pushRound(_ round: Round) {
        guard let ld = data else { return }

        let fixtureItems: [FixturePushItem] = round.fixtureIds.compactMap { fid in
            guard let m = ld.matches.first(where: { $0.id == fid }) else { return nil }
            let home = ld.teamsById[m.homeTeamId]?.name ?? "Home"
            let away = ld.teamsById[m.awayTeamId]?.name ?? "Away"
            return FixturePushItem(fixtureId: fid, home: home, away: away, kickoff: m.kickoff)
        }

        // Lazily mint cloudGameToken on first push for this game.
        if game.cloudGameTokenRaw == nil {
            game.cloudGameTokenRaw = UUID().uuidString.lowercased()
        }
        guard let gameToken = game.cloudGameToken else { return }

        // Build fixture-level TeamRefs for eligible-team computation (LMS only).
        // Scoped per fixture (not deduped by team) — a team playing twice in
        // the round appears twice so the PWA/picker can record which fixture a
        // pick is backing.
        let fixtureTeamRefs: [TeamRef] = round.fixtureIds.flatMap { fid -> [TeamRef] in
            guard let m = ld.matches.first(where: { $0.id == fid }) else { return [] }
            let home = ld.teamsById[m.homeTeamId]
            let away = ld.teamsById[m.awayTeamId]
            var refs: [TeamRef] = []
            if let home {
                refs.append(TeamRef(id: home.externalId, name: home.name,
                                     position: ld.standingsByTeam[home.externalId]?.position,
                                     fixtureId: fid, opponentName: away?.name))
            }
            if let away {
                refs.append(TeamRef(id: away.externalId, name: away.name,
                                     position: ld.standingsByTeam[away.externalId]?.position,
                                     fixtureId: fid, opponentName: home?.name))
            }
            return refs
        }
        let standingsKnown = fixtureTeamRefs.contains { $0.position != nil }
        let allowRepeats = game.allowRepeats
        let mode = game.mode
        let roundNumber = round.roundNumber
        let deadline = round.deadline
        let gameName = game.name

        // Resolve roster-member tokens synchronously before the async task
        // (avoids SwiftData main-actor access from a background context).
        // Self-heal: players added before rosterMemberId was tracked get it
        // written here so subsequent pushes use the UUID directly.
        let playerTokenMap: [UUID: String] = {
            var dict: [UUID: String] = [:]
            for player in game.activePlayers where !player.isManager {
                let member: RosterMember?
                if let memberId = player.rosterMemberId {
                    let fd = FetchDescriptor<RosterMember>(predicate: #Predicate { $0.id == memberId })
                    member = (try? context.fetch(fd))?.first
                } else {
                    let name = player.name
                    let fd = FetchDescriptor<RosterMember>(predicate: #Predicate { $0.name == name })
                    member = (try? context.fetch(fd))?.first
                    if let m = member { player.rosterMemberId = m.id }  // self-heal
                }
                if let rawToken = member?.submissionTokenRaw {
                    dict[player.id] = rawToken.lowercased()
                }
            }
            return dict
        }()

        // Last 8 hex chars of the manager's player UUID — used by the PWA to
        // identify which manager owns each game.
        let managerSuffix: String? = game.players.first(where: { $0.isManager }).map {
            String($0.id.uuidString.replacingOccurrences(of: "-", with: "").suffix(8)).lowercased()
        }

        let jokerEnabled = game.predictorJokerEnabled
        let linkedPlayers = game.activePlayers.filter { !$0.isManager && playerTokenMap[$0.id] != nil }

        let trimmedManagerName: String? = {
            let n = managerName.trimmingCharacters(in: .whitespacesAndNewlines)
            return n.isEmpty ? nil : n
        }()

        Task {
            var playerItems: [PlayerPushItem] = []
            for player in linkedPlayers {
                guard let token = playerTokenMap[player.id] else { continue }
                let eligibleTeams: [EligibleTeam]
                if mode == .lms {
                    let used = GameLogicService.usedTeamIds(for: player)
                    let ordered = GameEngine.orderedAvailableTeams(
                        fixtureTeams: fixtureTeamRefs,
                        used: used,
                        allowRepeats: allowRepeats,
                        standingsKnown: standingsKnown
                    )
                    eligibleTeams = ordered.map {
                        EligibleTeam(id: $0.id, name: $0.name, fixtureId: $0.fixtureId, opponentName: $0.opponentName)
                    }
                } else {
                    eligibleTeams = fixtureTeamRefs.map {
                        EligibleTeam(id: $0.id, name: $0.name, fixtureId: $0.fixtureId, opponentName: $0.opponentName)
                    }
                }
                playerItems.append(PlayerPushItem(
                    token: token,
                    localPlayerId: player.id.uuidString.lowercased(),
                    eligibleTeams: eligibleTeams.isEmpty ? nil : eligibleTeams
                ))
            }

            do {
                try await SubmissionsClient.shared.pushRound(
                    gameToken: gameToken,
                    mode: mode.rawValue,
                    roundNumber: roundNumber,
                    deadline: deadline,
                    gameName: gameName,
                    fixtures: fixtureItems,
                    jokerEnabled: jokerEnabled,
                    managerSuffix: managerSuffix,
                    managerName: trimmedManagerName,
                    players: playerItems
                )
            } catch {
                submissionsLog.warning("Round push failed: \(error.localizedDescription)")
            }
        }
    }
}
