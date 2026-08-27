import SwiftUI
import SwiftData

/// Internal, not private — `GameSummaryRow`'s Next Up button constructs this
/// screen with `autoOpenSheet: .results` etc. from the Games portal, so the
/// case names need to be visible outside this file.
enum KillerSheetV2: String, Identifiable {
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
/// per-game Submission Queue entry point — Games' SUBMISSIONS tile
/// (see `GamesPortalViewV2`) reaches every game's submissions already.
struct KillerGameDetailViewV2: View {
    @Environment(\.modelContext) private var context
    @Environment(Entitlements.self) private var entitlements
    @AppStorage("pwaSubmissionsEnabled") private var pwaSubmissionsEnabled = false
    @Query private var allMembers: [RosterMember]

    @Bindable var game: Game
    /// Set when pushed from the Games portal's Next Up button (see
    /// `GameSummaryRow`) — opens straight into that sheet instead of landing
    /// on the plain detail screen.
    var autoOpenSheet: KillerSheetV2?
    /// Same idea as `autoOpenSheet`, for the `.addPlayers` Next Up case.
    var autoShowAddPlayers = false
    @State private var showingAddPlayers = false
    @State private var sheet: KillerSheetV2?
    @State private var pendingRemovePlayer: Player?
    /// Header export/rename controls — see `V2GameHeaderActions`.
    @State private var headerActions = V2GameHeaderActionsModel(exporter: .killer)

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
    private var currentPhase: KillerPhase? {
        guard let round = currentRound ?? openRound else { return nil }
        return KillerScoringService.phase(for: round, game: game)
    }
    private var latestClosedRound: Round? { roundContext.latestClosedRound }
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
            V2GameHeaderActions(game: game, model: headerActions)
        }
        .v2GameHeaderActions(game: game, model: headerActions)
        .onAppear {
            if autoShowAddPlayers { showingAddPlayers = true }
            guard let autoOpenSheet else { return }
            sheet = autoOpenSheet
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
        V2GamePlayersCard(
            players: sortedPlayers,
            tint: V2Theme.Mode.killer,
            pwaEnabled: pwaEnabled,
            rosterMember: rosterMember(for:),
            onRemove: { pendingRemovePlayer = $0 },
            onAdd: { showingAddPlayers = true }
        )
    }

    /// Also clears any Kill Phase hit targets pointing at this player before
    /// removal — the one place Killer's remove differs from LMS/Predictor's.
    private func removePlayer(_ player: Player) {
        KillerScoringService.clearHitTargets(referencing: player, in: game)
        game.players.removeAll { $0.id == player.id }
        context.delete(player)
        pendingRemovePlayer = nil
    }
}
