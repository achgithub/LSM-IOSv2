import SwiftUI
import SwiftData

private enum PredictorSheetV2: String, Identifiable {
    case open, predictions, results, standings
    case shareFixtures, shareEntryClosed, shareWeeklyResults, shareLeague, shareWinner
    var id: String { rawValue }
}

/// Card restyle of `PredictorGameDetailView`. Same actions/scope as the
/// original (rename, remove player, edit fixtures, PWA resend, all 5 share
/// cards, tutorial anchors) — only "Enter Predictions" routes to the new
/// `PredictionsEntryViewV2`; every other sheet (standings, results entry,
/// share cards) still opens the existing unstyled screen, matching the
/// portal's "outer shell first, inner sheets next phase" pattern. The
/// original view is untouched. No per-game Submission Queue entry point —
/// the always-visible Home/Games bell (`AppHeader`) reaches every game's
/// submissions already.
struct PredictorGameDetailViewV2: View {
    @Environment(\.modelContext) private var context

    @Bindable var game: Game
    @State private var showingAddPlayers = false
    @State private var sheet: PredictorSheetV2?
    @State private var pendingRemovePlayer: Player?
    @State private var pendingEditFixtures = false
    @State private var renaming = false
    @State private var renameText = ""
    /// CSV export (manual backup) — mirrors LMS's `GameDetailView`.
    @State private var isPreparingExport = false
    @State private var exportFiles: [URL]?
    @State private var exportError: String?

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
    private func incompletePlayers(for round: Round) -> [Player] {
        PredictorScoringService.incompletePlayers(round: round, game: game)
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: V2Theme.Spacing.section) {
                infoCard
                roundCard
                if latestClosedRound != nil { shareCard }
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
                OpenRoundViewV2(game: game)
            case .predictions:
                if let round = openRound { PredictionsEntryViewV2(game: game, round: round) }
            case .results:
                if let round = openRound { PredictorResultsEntryViewV2(game: game, round: round) }
            case .standings:
                PredictorStandingsViewV2(game: game)
            case .shareFixtures:
                if let round = openRound {
                    PredictorShareView(game: game, round: round, type: .fixtures)
                }
            case .shareEntryClosed:
                if let round = openRound ?? latestClosedRound {
                    PredictorShareView(game: game, round: round, type: .entryClosed)
                }
            case .shareWeeklyResults:
                if let round = latestClosedRound {
                    PredictorShareView(game: game, round: round, type: .weeklyResults)
                }
            case .shareLeague:
                if let round = latestClosedRound {
                    PredictorShareView(game: game, round: round, type: .league)
                }
            case .shareWinner:
                if let round = latestClosedRound {
                    PredictorShareView(game: game, round: round, type: .winner)
                }
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
        .confirmationDialog(
            "Edit fixtures?",
            isPresented: $pendingEditFixtures,
            titleVisibility: .visible
        ) {
            Button("Edit Fixtures", role: .destructive) { resetOpenRound() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This resets the round so you can reselect fixtures. Any predictions already entered are cleared. This can't be undone.")
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
                    .foregroundStyle(V2Theme.Mode.predictor)
                }
            }
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
                        V2StatusBadge(label: round.status.label, tint: V2Theme.accent)
                    }
                    PrimaryButton(title: "Enter Predictions") { sheet = .predictions }
                        .tutorialAnchor(id: "pred.enterPredictions")
                    ActionRow(title: "Enter Results / Close", icon: "flag.checkered") { sheet = .results }
                        .tutorialAnchor(id: "pred.enterResults")
                    ActionRow(title: "Edit Fixtures", icon: "pencil", tint: V2Theme.danger) { pendingEditFixtures = true }
                    if !incompletePlayers(for: round).isEmpty {
                        let names = incompletePlayers(for: round).map(\.name).joined(separator: ", ")
                        Text("Waiting on predictions: \(names)")
                            .font(.caption).foregroundStyle(V2Theme.textTertiary)
                    }
                    ActionRow(title: "Share Fixtures Card", icon: "square.and.arrow.up") { AdGate.run { sheet = .shareFixtures } }
                    ActionRow(title: "Share Entry Closed Card", icon: "square.and.arrow.up", isEnabled: round.deadline < Date()) {
                        AdGate.run { sheet = .shareEntryClosed }
                    }
                } else {
                    PrimaryButton(title: "Open Round", isEnabled: game.players.count >= 2) { sheet = .open }
                        .tutorialAnchor(id: "pred.openRound")
                }
            }
        }
    }

    // MARK: - Share

    private var shareCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Share")
                ActionRow(title: "Share Weekly Results", icon: "square.and.arrow.up") { AdGate.run { sheet = .shareWeeklyResults } }
                    .tutorialAnchor(id: "pred.shareResults")
                ActionRow(title: "Share League Table", icon: "square.and.arrow.up") { AdGate.run { sheet = .shareLeague } }
                ActionRow(title: "Share Final Standings", icon: "square.and.arrow.up") { AdGate.run { sheet = .shareWinner } }
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
                                    V2StatusBadge(label: "you", tint: V2Theme.Mode.predictor)
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
                ActionRow(title: "Add Players", icon: "person.badge.plus") { showingAddPlayers = true }
                    .tutorialAnchor(id: "pred.addPlayers")
            }
        }
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

    private func resetOpenRound() {
        guard let round = openRound else { return }
        game.rounds.removeAll { $0.id == round.id }
        context.delete(round)
    }

    /// Manual backup: export the game's settings + full prediction history
    /// as two CSV files via the share sheet. Mirrors LMS's `exportGame()`.
    private func exportGame() async {
        isPreparingExport = true
        defer { isPreparingExport = false }
        do {
            let data = try await LeagueData.load(for: game.leagues)
            exportFiles = try PredictorExportFiles.write(for: game, data: data)
        } catch {
            exportError = AppString("Couldn't prepare the export. Please try again.")
        }
    }

    /// Full-fidelity JSON hand-off to another manager — not the CSV backup
    /// above. PWA links never transfer (acknowledged in the UI elsewhere);
    /// the receiving manager mints fresh ones if they use PWA submissions.
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
