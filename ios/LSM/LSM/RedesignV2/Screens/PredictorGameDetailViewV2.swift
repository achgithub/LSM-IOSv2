import SwiftUI
import SwiftData

/// Internal, not private — `GameSummaryRow`'s Next Up button constructs this
/// screen with `autoOpenSheet: .results` etc. from the Games portal, so the
/// case names need to be visible outside this file.
enum PredictorSheetV2: String, Identifiable {
    case open, predictions, results, standings
    case shareFixtures, shareEntryClosed, shareWeeklyResults, shareLeague, shareWinner
    var id: String { rawValue }
}

/// Card restyle of `PredictorGameDetailView`. Same actions/scope as the
/// original (rename, remove player, edit fixtures, PWA resend, all 5 share
/// cards, tutorial anchors) — "Enter Predictions" and "Add Players" route to
/// their new V2 screens; every other sheet (standings, results entry, share
/// cards) still opens the existing unstyled screen, matching the portal's
/// "outer shell first, inner sheets next phase" pattern. The original view
/// is untouched. No per-game Submission Queue entry point — Games'
/// SUBMISSIONS tile (see `GamesPortalViewV2`) reaches every game's
/// submissions already.
struct PredictorGameDetailViewV2: View {
    @Environment(\.modelContext) private var context
    @Environment(Entitlements.self) private var entitlements
    @AppStorage("pwaSubmissionsEnabled") private var pwaSubmissionsEnabled = false
    @Query private var allMembers: [RosterMember]

    @Bindable var game: Game
    /// Set when pushed from the Games portal's Next Up button (see
    /// `GameSummaryRow`) — opens straight into that sheet instead of landing
    /// on the plain detail screen.
    var autoOpenSheet: PredictorSheetV2?
    @State private var showingAddPlayers = false
    @State private var sheet: PredictorSheetV2?
    @State private var pendingRemovePlayer: Player?
    @State private var pendingEditFixtures = false
    /// Header export/rename controls — see `V2GameHeaderActions`.
    @State private var headerActions = V2GameHeaderActionsModel(exporter: .predictor)

    private var roundContext: V2GameRoundContext { V2GameRoundContext(game: game) }
    private var sortedPlayers: [Player] { roundContext.sortedPlayers }

    private var pwaEnabled: Bool { entitlements.canUseCloud && pwaSubmissionsEnabled }

    /// `Player` (per-game) -> `RosterMember` (roster-level identity, where the
    /// submission link actually lives) — nil for the manager's own entry or a
    /// player typed directly with no roster member.
    private func rosterMember(for player: Player) -> RosterMember? {
        guard let id = player.rosterMemberId else { return nil }
        return allMembers.first { $0.id == id }
    }

    private var currentRound: Round? { roundContext.currentRound }
    private var openRound: Round? { roundContext.openRound }
    private var latestClosedRound: Round? { roundContext.latestClosedRound }
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .v2TrophyRoomScene()
        .v2FloatingHeader(game.name) {
            V2GameHeaderActions(game: game, model: headerActions)
        }
        .v2GameHeaderActions(game: game, model: headerActions)
        .onAppear {
            guard let autoOpenSheet else { return }
            sheet = autoOpenSheet
        }
        .sheet(isPresented: $showingAddPlayers) { AddPlayersViewV2(game: game) }
        .sheet(item: $sheet) { which in
            switch which {
            case .open:
                OpenRoundViewV2(game: game, tint: V2Theme.Mode.predictor)
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
        Card(floating: true) {
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
        Card(floating: true) {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "This Round")
                if let round = openRound {
                    HStack {
                        Text("Round \(round.roundNumber)")
                            .font(V2Theme.Typography.rowTitle)
                            .foregroundStyle(V2Theme.textPrimary)
                        Spacer()
                        V2StatusBadge(label: round.status.label, tint: V2Theme.Mode.predictor)
                    }
                    PrimaryButton(title: "Enter Predictions", tint: V2Theme.Mode.predictor) { sheet = .predictions }
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
                    PrimaryButton(title: "Open Round", isEnabled: game.players.count >= 2, tint: V2Theme.Mode.predictor) { sheet = .open }
                        .tutorialAnchor(id: "pred.openRound")
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
                    .tutorialAnchor(id: "pred.shareResults")
                ActionRow(title: "Share League Table", icon: "square.and.arrow.up") { AdGate.run { sheet = .shareLeague } }
                ActionRow(title: "Share Final Standings", icon: "square.and.arrow.up") { AdGate.run { sheet = .shareWinner } }
            }
        }
    }

    // MARK: - Players

    private var playersCard: some View {
        V2GamePlayersCard(
            players: sortedPlayers,
            tint: V2Theme.Mode.predictor,
            pwaEnabled: pwaEnabled,
            addPlayersTutorialAnchorId: "pred.addPlayers",
            rosterMember: rosterMember(for:),
            onRemove: { pendingRemovePlayer = $0 },
            onAdd: { showingAddPlayers = true }
        )
    }

    private func removePlayer(_ player: Player) {
        game.players.removeAll { $0.id == player.id }
        context.delete(player)
        pendingRemovePlayer = nil
    }

    private func resetOpenRound() {
        guard let round = openRound else { return }
        game.rounds.removeAll { $0.id == round.id }
        context.delete(round)
    }
}
