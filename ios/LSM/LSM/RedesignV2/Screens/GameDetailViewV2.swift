import SwiftUI
import SwiftData

/// Internal, not private — `GameSummaryRow`'s Next Up button constructs this
/// screen with `autoOpenSheet: .results` etc. from the Games portal, so the
/// case names need to be visible outside this file.
enum LMSSheetV2: String, Identifiable {
    case open, picks, results, declare, summaryFixtures, summaryPicks, summaryResults, summaryOutcome, standings
    var id: String { rawValue }
}

/// Card restyle of `GameDetailView` (LMS). Same actions/scope as the
/// original (rename, remove player, edit fixtures, PWA resend, share cards,
/// the tie-resolution state machine) — every sheet still opens the existing
/// unstyled v1 screen except the ones restyled in this pass (Open Round,
/// Picks Entry, Results Entry, Declare Winners, Tie Resolution, Add Players);
/// share cards stay v1 (out of scope — see `SummaryShareView`). The original
/// view is untouched. No per-game Submission Queue entry point — Games'
/// SUBMISSIONS tile (see `GamesPortalViewV2`) reaches every game's
/// submissions already.
struct GameDetailViewV2: View {
    @Environment(\.modelContext) private var context
    @Environment(Entitlements.self) private var entitlements
    @AppStorage("pwaSubmissionsEnabled") private var pwaSubmissionsEnabled = false
    @Query private var allMembers: [RosterMember]

    @Bindable var game: Game
    /// Set when pushed from the Games portal's Next Up button (see
    /// `GameSummaryRow`) — opens straight into that sheet instead of landing
    /// on the plain detail screen, without duplicating this file's own
    /// tie-resolution/auto-open-next-round state machine to do it.
    var autoOpenSheet: LMSSheetV2?
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
    /// Header export/rename controls — see `V2GameHeaderActions`.
    @State private var headerActions = V2GameHeaderActionsModel(exporter: .lms)

    private var roundContext: V2GameRoundContext { V2GameRoundContext(game: game) }
    private var sortedPlayers: [Player] { roundContext.sortedPlayers }

    private var pwaEnabled: Bool { entitlements.canUseCloud && pwaSubmissionsEnabled }

    /// `Player` (per-game) -> `RosterMember` (roster-level identity, where the
    /// submission link actually lives) — nil for the manager's own entry or a
    /// player typed directly with no roster member. Looked up in the
    /// already-fetched `allMembers` rather than a fresh `FetchDescriptor` per
    /// row/render (see `PWARoundPusher`'s version of this lookup, used
    /// one-off in an async push where that cost doesn't repeat per render).
    private func rosterMember(for player: Player) -> RosterMember? {
        guard let id = player.rosterMemberId else { return nil }
        return allMembers.first { $0.id == id }
    }

    private var currentRound: Round? { roundContext.currentRound }
    private var openRound: Round? { roundContext.openRound }
    private var latestClosedRound: Round? { roundContext.latestClosedRound }
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
                }
                .foregroundStyle(V2Theme.Mode.lms)
            }
        }
    }

    // MARK: - This round (state machine — mirrors v1 GameDetailView.roundSection)

    @ViewBuilder
    private var roundCard: some View {
        Card(floating: true) {
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
            Card(floating: true) {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Manually declare winner(s)")
                    ActionRow(title: "Declare Winner(s)…", icon: "trophy", isEnabled: latestClosedRound != nil && !game.activePlayers.isEmpty) { sheet = .declare }
                }
            }
        }
    }

    // MARK: - Players

    private var playersCard: some View {
        V2GamePlayersCard(
            players: sortedPlayers,
            tint: V2Theme.Mode.lms,
            pwaEnabled: pwaEnabled,
            showsStatus: true,
            rosterMember: rosterMember(for:),
            onRemove: { pendingRemovePlayer = $0 },
            onAdd: { showingAddPlayers = true }
        )
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
}
