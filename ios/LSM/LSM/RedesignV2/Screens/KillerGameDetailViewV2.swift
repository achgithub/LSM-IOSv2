import SwiftUI
import SwiftData

private enum KillerSheetV2: String, Identifiable {
    case open, predictions, results, scratchpad, submissions
    case shareFixtures, sharePlayerKey, shareWeeklyResults, shareStandings, shareWinner
    var id: String { rawValue }
}

/// Card restyle of `KillerGameDetailView`. Same actions/scope as the
/// original (rename, remove player, PWA resend, submission queue, share
/// cards, scratchpad) — every sheet still opens the existing unstyled v1
/// screen (no restyled Killer entry/results screen exists yet), matching the
/// portal's "outer shell first, inner sheets next phase" pattern already
/// used for `PredictorGameDetailViewV2`. The original view is untouched.
struct KillerGameDetailViewV2: View {
    @Environment(\.modelContext) private var context
    @Environment(Entitlements.self) private var entitlements

    @Bindable var game: Game
    @State private var showingAddPlayers = false
    @State private var sheet: KillerSheetV2?
    @State private var pendingRemovePlayer: Player?
    @State private var renaming = false
    @State private var renameText = ""
    @State private var isResending = false
    @State private var resendMessage: String?
    @State private var lifecycleStatus: ManagerLifecycleStatus?
    /// CSV export (manual backup) — mirrors LMS's `GameDetailView`.
    @State private var isPreparingExport = false
    @State private var exportFiles: [URL]?
    @State private var exportError: String?

    @AppStorage("pwaSubmissionsEnabled") private var pwaSubmissionsEnabled = false
    @AppStorage(ManagerSettings.nameKey) private var managerName = ""

    private var sortedByLives: [Player] {
        game.players.sorted { a, b in
            let livesA = a.killerState?.lives ?? 0
            let livesB = b.killerState?.lives ?? 0
            if livesA != livesB { return livesA > livesB }
            let accA = a.killerState?.correctPredictions ?? 0
            let accB = b.killerState?.correctPredictions ?? 0
            if accA != accB { return accA > accB }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    private var sortedPlayers: [Player] {
        game.players.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var currentRound: Round? { game.currentRound }
    private var openRound: Round? {
        if let round = currentRound, round.status != .closed { return round }
        return nil
    }
    private var currentPhase: KillerPhase? {
        guard let round = currentRound ?? openRound else { return nil }
        return KillerScoringService.phase(for: round, game: game)
    }
    private var latestClosedRound: Round? {
        game.rounds.filter { $0.status == .closed }.max(by: { $0.roundNumber < $1.roundNumber })
    }
    private var openRoundComplete: Bool {
        guard let round = openRound else { return false }
        return KillerScoringService.allActivePlayersComplete(round: round, game: game)
    }

    private var canReachExistingCloudData: Bool {
        entitlements.canUseCloud || lifecycleStatus?.isPendingDelete == true
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: V2Theme.Spacing.section) {
                infoCard
                roundCard
                if latestClosedRound != nil { shareCard }
                livesCard
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
                Button { Task { await exportGame() } } label: {
                    if isPreparingExport {
                        ProgressView()
                    } else {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundStyle(V2Theme.textPrimary)
                    }
                }
                .disabled(isPreparingExport)
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
        .sheet(item: $sheet) { which in
            switch which {
            case .open:
                KillerOpenRoundView(game: game)
            case .predictions:
                if let round = openRound { KillerPredictionsEntryView(game: game, round: round) }
            case .results:
                if let round = openRound { KillerResultsEntryView(game: game, round: round) }
            case .scratchpad:
                if let round = openRound { KillerScratchpadEntryView(game: game, round: round) }
            case .submissions:
                if let round = openRound, let gameToken = game.cloudGameToken {
                    NavigationStack {
                        SubmissionQueueView(game: game, round: round, gameToken: gameToken)
                    }
                }
            case .shareFixtures:
                if let round = openRound { KillerShareView(game: game, round: round, type: .fixtures) }
            case .sharePlayerKey:
                if let round = openRound { KillerShareView(game: game, round: round, type: .playerKey) }
            case .shareWeeklyResults:
                if let round = latestClosedRound { KillerShareView(game: game, round: round, type: .weeklyResults) }
            case .shareStandings:
                if let round = latestClosedRound ?? openRound {
                    KillerShareView(game: game, round: round, type: .standings)
                }
            case .shareWinner:
                if let round = latestClosedRound { KillerShareView(game: game, round: round, type: .winner) }
            }
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
            Text("\(player.name) is removed from the game and their predictions deleted. This can't be undone.")
        }
    }

    // MARK: - Info

    private var infoCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    V2StatusBadge(gameStatus: game.status)
                    Spacer()
                    if let currentPhase {
                        Text(currentPhase == .build ? "Build Phase" : "Kill Phase")
                            .font(V2Theme.Typography.metadata)
                            .foregroundStyle(V2Theme.textSecondary)
                    }
                }
                if entitlements.canUseCloud && pwaSubmissionsEnabled, game.cloudGameToken != nil {
                    Button {
                        Task { await resend() }
                    } label: {
                        if isResending {
                            ProgressView()
                        } else {
                            Label("Resend to Player App", systemImage: "arrow.clockwise.icloud")
                        }
                    }
                    .disabled(isResending)
                    .foregroundStyle(V2Theme.textSecondary)
                    if let resendMessage {
                        Text(resendMessage).font(.caption).foregroundStyle(V2Theme.textTertiary)
                    }
                }
            }
        }
    }

    private func resend() async {
        isResending = true
        resendMessage = nil
        defer { isResending = false }
        let name = managerName
        do {
            try await PWARoundPusher.pushKiller(game: game, round: nil, managerName: name, context: context)
            resendMessage = AppString("Sent to Player App just now.")
        } catch {
            resendMessage = AppString("Send failed: \(error.localizedDescription)")
        }
    }

    // MARK: - This round

    @ViewBuilder
    private var roundCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "This Round")
                if let round = openRound {
                    HStack {
                        Text("Round \(round.roundNumber)")
                            .font(V2Theme.Typography.rowTitle)
                            .foregroundStyle(V2Theme.textPrimary)
                        Spacer()
                        V2StatusBadge(label: round.status.label, tint: V2Theme.Mode.killer)
                    }
                    actionRow(title: "Enter Predictions", icon: "checklist") { sheet = .predictions }
                    actionRow(title: "Scratchpad (Paste Picks)", icon: "text.badge.plus") { sheet = .scratchpad }
                    actionRow(title: "Enter Results / Close", icon: "flag.checkered") { sheet = .results }
                    if !openRoundComplete {
                        Text("Waiting on predictions before this round can close.")
                            .font(.caption).foregroundStyle(V2Theme.textTertiary)
                    }
                    actionRow(title: "Share Fixtures Card", icon: "square.and.arrow.up") { AdGate.run { sheet = .shareFixtures } }
                    if currentPhase == .kill {
                        actionRow(title: "Share Player Key Card", icon: "square.and.arrow.up") { AdGate.run { sheet = .sharePlayerKey } }
                    }
                    if canReachExistingCloudData && pwaSubmissionsEnabled, game.cloudGameToken != nil {
                        actionRow(title: "Submission Queue", icon: "tray.and.arrow.down") { sheet = .submissions }
                    }
                } else if game.status == .complete {
                    Text("Game complete.").font(.footnote).foregroundStyle(V2Theme.textSecondary)
                } else {
                    PrimaryButton(title: "Open Round", isEnabled: game.activePlayers.count >= 2, tint: V2Theme.Mode.killer) {
                        sheet = .open
                    }
                }
            }
        }
    }

    // MARK: - Share

    private var shareCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Share")
                actionRow(title: "Share Weekly Results", icon: "square.and.arrow.up") { AdGate.run { sheet = .shareWeeklyResults } }
                actionRow(title: "Share Accuracy Table", icon: "square.and.arrow.up") { AdGate.run { sheet = .shareStandings } }
                if game.status == .complete {
                    actionRow(title: "Share Final Result", icon: "square.and.arrow.up") { AdGate.run { sheet = .shareWinner } }
                }
            }
        }
    }

    // MARK: - Lives

    private var livesCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Lives")
                if game.players.isEmpty {
                    Text("No players yet.").font(.footnote).foregroundStyle(V2Theme.textSecondary)
                } else {
                    VStack(spacing: 8) {
                        ForEach(sortedByLives) { player in
                            HStack {
                                Text(player.name)
                                    .font(V2Theme.Typography.rowTitle)
                                    .foregroundStyle(V2Theme.textPrimary)
                                if player.status == .eliminated {
                                    Text("eliminated")
                                        .font(.caption2)
                                        .foregroundStyle(V2Theme.textTertiary)
                                }
                                Spacer()
                                Text(String(repeating: "❤️", count: max(0, player.killerState?.lives ?? 0)))
                                    .font(.caption)
                            }
                            .padding(10)
                            .background(V2Theme.pillBackground, in: RoundedRectangle(cornerRadius: V2Theme.Radius.row, style: .continuous))
                        }
                    }
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
                                    V2StatusBadge(label: "you", tint: V2Theme.Mode.killer)
                                }
                                Spacer()
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
                actionRow(title: "Add Players", icon: "person.badge.plus") { showingAddPlayers = true }
            }
        }
    }

    private func actionRow(title: String, icon: String, tint: Color = V2Theme.accent, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: icon)
                Spacer()
                Image(systemName: "chevron.right").font(.caption)
            }
        }
        .foregroundStyle(tint)
    }

    private func removePlayer(_ player: Player) {
        game.players.removeAll { $0.id == player.id }
        context.delete(player)
        pendingRemovePlayer = nil
    }

    private func commitRename() {
        let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        game.name = name
        try? context.save()
    }

    /// Manual backup: export the game's settings + full prediction history
    /// as two CSV files via the share sheet. Mirrors LMS's `exportGame()`.
    private func exportGame() async {
        isPreparingExport = true
        defer { isPreparingExport = false }
        do {
            let data = try await LeagueData.load(for: game.leagues)
            exportFiles = try KillerExportFiles.write(for: game, data: data)
        } catch {
            exportError = AppString("Couldn't prepare the export. Please try again.")
        }
    }
}
