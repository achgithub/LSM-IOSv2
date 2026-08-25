import SwiftUI
import SwiftData

private enum KillerSheetV2: String, Identifiable {
    case open, predictions, results, lives
    case shareFixtures, sharePlayerKey, shareWeeklyResults, shareStandings, shareWinner
    var id: String { rawValue }
}

/// Card restyle of `KillerGameDetailView`. Same actions/scope as the
/// original (rename, remove player, PWA resend, share cards) minus
/// Scratchpad — that was a v1 proof-of-concept, intentionally dropped from
/// V2. Predictions/Results/Lives/Add Players route to their own restyled V2
/// screens; the rest still open the original view. The original view is
/// untouched (bar the Add Players sheet target). No
/// per-game Submission Queue entry point — the always-visible Home/Games
/// bell (`AppHeader`) reaches every game's submissions already.
struct KillerGameDetailViewV2: View {
    @Environment(\.modelContext) private var context
    @Environment(Entitlements.self) private var entitlements
    @AppStorage("pwaSubmissionsEnabled") private var pwaSubmissionsEnabled = false
    @Query private var allMembers: [RosterMember]

    @Bindable var game: Game
    @State private var showingAddPlayers = false
    @State private var sheet: KillerSheetV2?
    @State private var pendingRemovePlayer: Player?
    @State private var renaming = false
    @State private var renameText = ""
    /// CSV export (manual backup) — mirrors LMS's `GameDetailView`.
    @State private var isPreparingExport = false
    @State private var exportFiles: [URL]?
    @State private var exportError: String?

    private var sortedPlayers: [Player] {
        game.players.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var pwaEnabled: Bool { entitlements.canUseCloud && pwaSubmissionsEnabled }

    /// `Player` (per-game) -> `RosterMember` (roster-level identity, where the
    /// submission link actually lives) — nil for the manager's own entry or a
    /// player typed directly with no roster member.
    private func rosterMember(for player: Player) -> RosterMember? {
        guard let id = player.rosterMemberId else { return nil }
        return allMembers.first { $0.id == id }
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .v2TrophyRoomScene()
        .v2FloatingHeader(game.name) {
            HStack(spacing: 10) {
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
                            .font(.body.weight(.semibold))
                            .foregroundStyle(V2Theme.textPrimary)
                            .frame(width: 36, height: 36)
                            .background(V2Theme.cardBackground, in: Circle())
                    }
                }
                Button {
                    renameText = game.name
                    renaming = true
                } label: {
                    Image(systemName: "pencil")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(V2Theme.textPrimary)
                        .frame(width: 36, height: 36)
                        .background(V2Theme.cardBackground, in: Circle())
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
        .sheet(isPresented: $showingAddPlayers) { AddPlayersViewV2(game: game) }
        .sheet(item: $sheet) { which in
            switch which {
            case .open:
                KillerOpenRoundViewV2(game: game)
            case .predictions:
                if let round = openRound { KillerPredictionsEntryViewV2(game: game, round: round) }
            case .results:
                if let round = openRound { KillerResultsEntryViewV2(game: game, round: round) }
            case .lives:
                KillerLivesViewV2(game: game)
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
        Card(floating: true) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    V2StatusBadge(gameStatus: game.status)
                    Spacer()
                    if let currentPhase {
                        Text("Round \(currentRound?.roundNumber ?? 0) · \(currentPhase == .build ? "Build Phase" : "Kill Phase")")
                            .font(V2Theme.Typography.metadata)
                            .foregroundStyle(V2Theme.textSecondary)
                    }
                }
                Button { sheet = .lives } label: {
                    HStack {
                        Label("Lives", systemImage: "heart.fill")
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption)
                    }
                }
                .foregroundStyle(V2Theme.Mode.killer)
            }
        }
    }

    // MARK: - This round

    @ViewBuilder
    private var roundCard: some View {
        Card(floating: true) {
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
                    PrimaryButton(title: "Enter Predictions", tint: V2Theme.Mode.killer) { sheet = .predictions }
                    ActionRow(title: "Enter Results / Close", icon: "flag.checkered") { sheet = .results }
                    if !openRoundComplete {
                        Text("Waiting on predictions before this round can close.")
                            .font(.caption).foregroundStyle(V2Theme.textTertiary)
                    }
                    ActionRow(title: "Share Fixtures Card", icon: "square.and.arrow.up") { AdGate.run { sheet = .shareFixtures } }
                    if currentPhase == .kill {
                        ActionRow(title: "Share Player Key Card", icon: "square.and.arrow.up") { AdGate.run { sheet = .sharePlayerKey } }
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
        Card(floating: true) {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Share")
                ActionRow(title: "Share Weekly Results", icon: "square.and.arrow.up") { AdGate.run { sheet = .shareWeeklyResults } }
                ActionRow(title: "Share Accuracy Table", icon: "square.and.arrow.up") { AdGate.run { sheet = .shareStandings } }
                if game.status == .complete {
                    ActionRow(title: "Share Final Result", icon: "square.and.arrow.up") { AdGate.run { sheet = .shareWinner } }
                }
            }
        }
    }

    // MARK: - Players

    private var playersCard: some View {
        Card(floating: true) {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Players (\(game.players.count))")
                if game.players.isEmpty {
                    Text("No players yet.").font(.footnote).foregroundStyle(V2Theme.textSecondary)
                } else {
                    VStack(spacing: 8) {
                        ForEach(sortedPlayers) { player in
                            playerRow(player)
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

    /// Tapping a roster-linked player opens `PlayerDetailViewV2` — same
    /// screen `PlayersViewV2` links to — so link mint/regenerate/remove
    /// queries can be handled right from the game without a trip to the
    /// Players tab. Players with no roster member render the same row inert.
    @ViewBuilder
    private func playerRow(_ player: Player) -> some View {
        if let member = rosterMember(for: player) {
            NavigationLink {
                PlayerDetailViewV2(member: member, pwaEnabled: pwaEnabled)
            } label: {
                playerRowContent(player, member: member)
            }
            .buttonStyle(.plain)
        } else {
            playerRowContent(player, member: nil)
        }
    }

    private func playerRowContent(_ player: Player, member: RosterMember?) -> some View {
        HStack {
            Text(player.name)
                .font(V2Theme.Typography.rowTitle)
                .foregroundStyle(V2Theme.textPrimary)
            if player.isManager {
                V2StatusBadge(label: "you", tint: V2Theme.Mode.killer)
            }
            Spacer()
            if pwaEnabled, let member {
                Image(systemName: member.submissionTokenRaw != nil ? "link" : "plus.circle")
                    .font(.caption)
                    .foregroundStyle(V2Theme.textSecondary)
            }
        }
        .padding(10)
        .background(V2Theme.pillBackground, in: RoundedRectangle(cornerRadius: V2Theme.Radius.row, style: .continuous))
    }

    private func removePlayer(_ player: Player) {
        KillerScoringService.clearHitTargets(referencing: player, in: game)
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

    /// Full-fidelity JSON hand-off to another manager — not the CSV backup
    /// above. PWA links never transfer; the receiving manager mints fresh
    /// ones if they use PWA submissions.
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
