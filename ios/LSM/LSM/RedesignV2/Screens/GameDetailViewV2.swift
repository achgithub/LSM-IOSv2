import SwiftUI
import SwiftData

private enum LMSSheetV2: String, Identifiable {
    case open, picks, results, declare, summaryFixtures, summaryPicks, summaryResults, summaryOutcome, submissions, standings
    var id: String { rawValue }
}

/// Card restyle of `GameDetailView` (LMS). Same actions/scope as the
/// original (rename, remove player, edit fixtures, PWA resend, submission
/// queue, share cards, the tie-resolution state machine) — every sheet
/// still opens the existing unstyled v1 screen except the ones restyled in
/// this pass (Open Round, Picks Entry, Results Entry, Declare Winners, Tie
/// Resolution); share cards stay v1 (out of scope — see `SummaryShareView`).
/// The original view is untouched.
struct GameDetailViewV2: View {
    @Environment(\.modelContext) private var context
    @Environment(Entitlements.self) private var entitlements

    @Bindable var game: Game
    @State private var showingAddPlayers = false
    @State private var sheet: LMSSheetV2?
    /// The tie resolution is presented at the top level (never stacked on the
    /// Results sheet — stacking and dismissing two sheets blanks the screen).
    /// `pendingResolve` is set when a close ends all-eliminated; once the
    /// Results sheet has dismissed we present the resolution.
    @State private var pendingResolve = false
    @State private var showResolve = false
    /// A resolution that reinstates players opens a follow-up round next.
    @State private var pendingAutoOpen: RoundType?
    @State private var autoOpenType: RoundType?
    @State private var pendingRemovePlayer: Player?
    @State private var pendingEditFixtures = false
    @State private var renaming = false
    @State private var renameText = ""
    @State private var lifecycleStatus: ManagerLifecycleStatus?
    /// CSV/Transfer export — mirrors Predictor/Killer V2.
    @State private var isPreparingExport = false
    @State private var exportFiles: [URL]?
    @State private var exportError: String?

    @AppStorage("pwaSubmissionsEnabled") private var pwaSubmissionsEnabled = false

    private var sortedPlayers: [Player] {
        game.players.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var currentRound: Round? { game.currentRound }
    private var openRound: Round? {
        if let round = currentRound, round.status != .closed { return round }
        return nil
    }
    private var latestClosedRound: Round? {
        game.rounds.filter { $0.status == .closed }.max(by: { $0.roundNumber < $1.roundNumber })
    }
    private var unresolvedTie: Bool {
        game.status == .active && openRound == nil
            && game.activePlayers.isEmpty && latestClosedRound != nil
    }
    private var lastRoundTied: [Player] {
        guard let round = latestClosedRound else { return [] }
        return game.players.filter { player in
            round.picks.contains { $0.player?.id == player.id }
        }
    }
    private var openRoundPicksComplete: Bool {
        guard let round = openRound, !round.picks.isEmpty else { return false }
        return !game.activePlayers.contains { player in
            !round.picks.contains { $0.player?.id == player.id }
        }
    }
    private var canReachExistingCloudData: Bool {
        entitlements.canUseCloud || lifecycleStatus?.isPendingDelete == true
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: V2Theme.Spacing.section) {
                infoCard
                roundCard
                declareCard
                playersCard
            }
            .padding(.horizontal, V2Theme.Spacing.horizontal)
            .padding(.vertical, V2Theme.Spacing.section)
        }
        .background(V2Theme.background.ignoresSafeArea())
        .v2Header(game.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    renameText = game.name
                    renaming = true
                } label: {
                    Image(systemName: "pencil")
                        .foregroundStyle(V2Theme.textPrimary)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if isPreparingExport {
                    ProgressView()
                } else {
                    Menu {
                        Button { Task { await exportGame() } } label: {
                            Label("Export as CSV (backup)", systemImage: "doc.text")
                        }
                        Button { Task { await exportForTransfer() } } label: {
                            Label("Export for Transfer", systemImage: "square.and.arrow.up.on.square")
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundStyle(V2Theme.textPrimary)
                    }
                }
            }
        }
        .task {
            if !entitlements.canUseCloud {
                lifecycleStatus = await ManagerLifecycleClient.shared.status()
            }
        }
        .alert("Rename game", isPresented: $renaming) {
            TextField("Game name", text: $renameText)
            Button("Rename") { commitRename() }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(item: Binding(
            get: { exportFiles.map(ExportShareItem.init) },
            set: { if $0 == nil { exportFiles = nil } }
        )) { item in
            ActivityShareView(items: item.urls)
        }
        .alert("Export Failed", isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError ?? "")
        }
        .sheet(isPresented: $showingAddPlayers) { AddPlayersView(game: game) }
        .sheet(item: $sheet, onDismiss: presentPendingResolve) { which in
            switch which {
            case .open:
                OpenRoundViewV2(game: game, tint: V2Theme.Mode.lms)
            case .picks:
                if let round = openRound { PicksEntryViewV2(game: game, round: round) }
            case .results:
                if let round = openRound {
                    ResultsEntryViewV2(game: game, round: round, pendingResolve: $pendingResolve)
                }
            case .declare:
                DeclareWinnersViewV2(game: game) {}
            case .summaryFixtures:
                if let round = openRound {
                    SummaryShareView(game: game, round: round, type: .fixtures)
                }
            case .summaryPicks:
                if let round = openRound {
                    SummaryShareView(game: game, round: round, type: .picks)
                }
            case .summaryResults:
                if let round = latestClosedRound {
                    SummaryShareView(game: game, round: round, type: .results)
                }
            case .summaryOutcome:
                if let ending = game.lastOutcome, let round = latestClosedRound {
                    SummaryShareView(game: game, round: round, type: .outcome(ending))
                }
            case .submissions:
                if let gameToken = game.cloudGameToken {
                    NavigationStack {
                        SubmissionInboxViewV2(filterGameToken: gameToken)
                    }
                }
            case .standings:
                LMSStandingsViewV2(game: game)
            }
        }
        // Tie resolution at the top level — presented only after the Results
        // sheet has fully dismissed, so two sheets never dismiss at once
        // (which blanked the screen). Manual "Resolve Round" presents it the
        // same way.
        .sheet(isPresented: $showResolve, onDismiss: presentPendingAutoOpen) {
            TieResolutionViewV2(game: game, tiedPlayers: lastRoundTied) { followUp in
                pendingAutoOpen = followUp
            }
        }
        .sheet(item: $autoOpenType) { type in
            OpenRoundViewV2(game: game, roundType: type, tint: V2Theme.Mode.lms)
        }
        .confirmationDialog(
            "Remove \(pendingRemovePlayer?.name ?? "")?",
            isPresented: Binding(get: { pendingRemovePlayer != nil }, set: { if !$0 { pendingRemovePlayer = nil } }),
            titleVisibility: .visible,
            presenting: pendingRemovePlayer
        ) { player in
            Button("Remove \(player.name)", role: .destructive) { removePlayer(player) }
            Button("Cancel", role: .cancel) {}
        } message: { player in
            Text("\(player.name) is removed from the game and their picks deleted. This can't be undone.")
        }
        .confirmationDialog(
            "Edit fixtures?",
            isPresented: $pendingEditFixtures,
            titleVisibility: .visible
        ) {
            Button("Edit Fixtures", role: .destructive) { resetOpenRound() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This resets the round so you can reselect fixtures. Any picks already made are cleared. This can't be undone.")
        }
    }

    // MARK: - Info

    private var infoCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    V2StatusBadge(gameStatus: game.status)
                    Spacer()
                    Text("Round \(currentRound?.roundNumber ?? 0)")
                        .font(V2Theme.Typography.metadata)
                        .foregroundStyle(V2Theme.textSecondary)
                }
                Button { sheet = .standings } label: {
                    HStack {
                        Label("Standings", systemImage: "list.number")
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption)
                    }
                }
                .foregroundStyle(V2Theme.Mode.lms)
                if canReachExistingCloudData && pwaSubmissionsEnabled, game.cloudGameToken != nil {
                    // Not gated on an open round — the Home/Games bell already
                    // reaches this game's submissions regardless of round
                    // state, so hiding this entry point behind "has an open
                    // round" was just an inconsistent extra gate. Kept as its
                    // own `if` (looser `canReachExistingCloudData`, not
                    // `entitlements.canUseCloud`) so a downgraded manager in
                    // their pending-delete grace period can still reach
                    // existing submissions.
                    Button {
                        sheet = .submissions
                    } label: {
                        Label("Submission Queue", systemImage: "tray.and.arrow.down")
                    }
                    .foregroundStyle(V2Theme.textSecondary)
                }
            }
        }
    }

    // MARK: - This round (state machine — mirrors v1 GameDetailView.roundSection)

    @ViewBuilder
    private var roundCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: game.status == .complete ? "Result" : "This Round")

                if game.status == .complete {
                    let winners = game.players.filter { $0.status == .winner }
                    HStack {
                        Text(winners.count == 1 ? "Winner" : "Winners")
                            .font(V2Theme.Typography.rowTitle).foregroundStyle(V2Theme.textPrimary)
                        Spacer()
                        Text(winners.map(\.name).joined(separator: ", "))
                            .font(.footnote).foregroundStyle(V2Theme.textSecondary)
                    }
                    ActionRow(title: "Share Results Card", icon: "square.and.arrow.up", isEnabled: latestClosedRound != nil) { AdGate.run { sheet = .summaryResults } }
                    if let ending = game.lastOutcome {
                        ActionRow(title: "Share \(ending.headline) Card", icon: "square.and.arrow.up", isEnabled: latestClosedRound != nil) { AdGate.run { sheet = .summaryOutcome } }
                    }

                } else if let round = openRound {
                    HStack {
                        Text("Round \(round.roundNumber)")
                            .font(V2Theme.Typography.rowTitle).foregroundStyle(V2Theme.textPrimary)
                        Spacer()
                        V2StatusBadge(label: round.status.label, tint: V2Theme.Mode.lms)
                    }
                    if round.roundType != .normal, let ending = game.lastOutcome {
                        ActionRow(title: "Share \(ending.headline) Card", icon: "square.and.arrow.up") { AdGate.run { sheet = .summaryOutcome } }
                    }
                    PrimaryButton(title: "Enter Picks", tint: V2Theme.Mode.lms) { sheet = .picks }
                    ActionRow(title: "Enter Results / Close", icon: "flag.checkered", tint: V2Theme.accent, isEnabled: openRoundPicksComplete) {
                        sheet = .results
                    }
                    if !openRoundPicksComplete, !round.picks.isEmpty || !game.activePlayers.isEmpty {
                        let missing = game.activePlayers.filter { player in
                            !round.picks.contains { $0.player?.id == player.id }
                        }
                        if !missing.isEmpty {
                            Text("Waiting on: \(missing.map(\.name).joined(separator: ", "))")
                                .font(.caption).foregroundStyle(V2Theme.textTertiary)
                        }
                    }
                    ActionRow(title: "Edit Fixtures", icon: "pencil", tint: V2Theme.danger) { pendingEditFixtures = true }
                    ActionRow(title: "Share Fixtures Card", icon: "square.and.arrow.up") { AdGate.run { sheet = .summaryFixtures } }
                    ActionRow(title: "Share Picks Card", icon: "square.and.arrow.up", isEnabled: openRoundPicksComplete) { AdGate.run { sheet = .summaryPicks } }

                } else if unresolvedTie {
                    HStack {
                        Text("Round \(latestClosedRound?.roundNumber ?? 0)")
                            .font(V2Theme.Typography.rowTitle).foregroundStyle(V2Theme.textPrimary)
                        Spacer()
                        V2StatusBadge(label: "No clear winner", tint: V2Theme.warning)
                    }
                    ActionRow(title: "Resolve Round", icon: "exclamationmark.triangle", tint: V2Theme.warning) { showResolve = true }
                    ActionRow(title: "Share Results Card", icon: "square.and.arrow.up", isEnabled: latestClosedRound != nil) { AdGate.run { sheet = .summaryResults } }

                } else {
                    if latestClosedRound != nil {
                        ActionRow(title: "Share Results Card", icon: "square.and.arrow.up") { AdGate.run { sheet = .summaryResults } }
                    }
                    PrimaryButton(title: "Open Round", isEnabled: game.activePlayers.count >= 2, tint: V2Theme.Mode.lms) {
                        sheet = .open
                    }
                }
            }
        }
    }

    // MARK: - Declare winners

    @ViewBuilder
    private var declareCard: some View {
        if game.status != .complete {
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Manually declare winner(s)")
                    ActionRow(title: "Declare Winner(s)…", icon: "trophy", isEnabled: latestClosedRound != nil && !game.activePlayers.isEmpty) { sheet = .declare }
                }
            }
        }
    }

    // MARK: - Players

    private var playersCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Players (\(game.players.count))")
                if game.players.isEmpty {
                    Text("No players yet.").font(.footnote).foregroundStyle(V2Theme.textSecondary)
                } else {
                    VStack(spacing: 8) {
                        ForEach(sortedPlayers) { player in
                            HStack {
                                Text(player.name)
                                    .font(V2Theme.Typography.rowTitle)
                                    .foregroundStyle(V2Theme.textPrimary)
                                if player.isManager {
                                    V2StatusBadge(label: "you", tint: V2Theme.Mode.lms)
                                }
                                Spacer()
                                if player.status != .active {
                                    Text(player.status.label)
                                        .font(.caption)
                                        .foregroundStyle(player.status == .winner ? V2Theme.accent : V2Theme.danger)
                                }
                            }
                            .padding(10)
                            .background(V2Theme.pillBackground, in: RoundedRectangle(cornerRadius: V2Theme.Radius.row, style: .continuous))
                            .contextMenu {
                                Button(role: .destructive) { pendingRemovePlayer = player } label: {
                                    Label("Remove", systemImage: "person.fill.xmark")
                                }
                            }
                        }
                    }
                }
                ActionRow(title: "Add Players", icon: "person.badge.plus") { showingAddPlayers = true }
            }
        }
    }

    // MARK: - Actions

    private func resetOpenRound() {
        guard let round = openRound else { return }
        let type = round.roundType
        game.rounds.removeAll { $0.id == round.id }
        context.delete(round)
        autoOpenType = type
    }

    private func removePlayer(_ player: Player) {
        game.players.removeAll { $0.id == player.id }
        context.delete(player)
        pendingRemovePlayer = nil
    }

    private func presentPendingResolve() {
        guard pendingResolve else { return }
        pendingResolve = false
        showResolve = true
    }

    private func presentPendingAutoOpen() {
        guard let type = pendingAutoOpen else { return }
        pendingAutoOpen = nil
        autoOpenType = type
    }

    private func commitRename() {
        let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        game.name = name
        try? context.save()
    }

    private func exportGame() async {
        isPreparingExport = true
        defer { isPreparingExport = false }
        do {
            let data = try await LeagueData.load(for: game.leagues)
            exportFiles = try GameExportFiles.write(for: game, data: data)
        } catch {
            exportError = AppString("Couldn't prepare the export. Please try again.")
        }
    }

    private func exportForTransfer() async {
        isPreparingExport = true
        defer { isPreparingExport = false }
        do {
            exportFiles = try [GameTransferFile.write(snapshot: GameTransferBuilder.snapshot(of: game), gameName: game.name)]
        } catch {
            exportError = AppString("Couldn't prepare the export. Please try again.")
        }
    }
}
