import SwiftUI
import SwiftData

private enum RoundSheet: String, Identifiable {
    case open, picks, results, declare, summaryPicks, summaryResults, summaryOutcome
    var id: String { rawValue }
}

/// Game detail: header, player roster, and the state-driven round actions
/// (open round → picks → results/close), plus the manager declare-winner override.
struct GameDetailView: View {
    @Environment(\.modelContext) private var context
    @Bindable var game: Game
    @State private var showingAddPlayers = false
    @State private var sheet: RoundSheet?
    /// The tie resolution is presented at the top level (never stacked on the
    /// Results sheet — stacking and dismissing two sheets blanks the screen).
    /// `pendingResolve` is set when a close ends all-eliminated; once the Results
    /// sheet has dismissed we present the resolution.
    @State private var pendingResolve = false
    @State private var showResolve = false
    /// A resolution that reinstates players opens a follow-up round next.
    @State private var pendingAutoOpen: RoundType?
    @State private var autoOpenType: RoundType?
    /// A player pending drop-out removal (awaiting the confirmation dialog).
    @State private var pendingRemovePlayer: Player?

    private var sortedPlayers: [Player] {
        game.players.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var currentRound: Round? { game.currentRound }
    private var openRound: Round? {
        if let round = currentRound, round.status != .closed { return round }
        return nil
    }

    /// Most recent closed round — source for a Results/Outcome card.
    private var latestClosedRound: Round? {
        game.rounds.filter { $0.status == .closed }.max(by: { $0.roundNumber < $1.roundNumber })
    }

    /// The last round closed with everyone eliminated and no resolution applied —
    /// the game needs a tie resolution before it can continue (recovery path).
    private var unresolvedTie: Bool {
        game.status == .active && openRound == nil
            && game.activePlayers.isEmpty && latestClosedRound != nil
    }
    /// Players who contested that final round — the tied group to resolve over.
    private var lastRoundTied: [Player] {
        guard let round = latestClosedRound else { return [] }
        return game.players.filter { player in
            round.picks.contains { $0.player?.id == player.id }
        }
    }

    /// A Picks card is shareable only while a round is open and every active
    /// player has a pick (picks complete) — never for a closed/empty round.
    private var openRoundPicksComplete: Bool {
        guard let round = openRound, !round.picks.isEmpty else { return false }
        return !game.activePlayers.contains { player in
            !round.picks.contains { $0.player?.id == player.id }
        }
    }

    var body: some View {
        List {
            infoSection
            roundSection
            summarySection
            playersSection
        }
        .navigationTitle(game.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingAddPlayers) { AddPlayersView(game: game) }
        .sheet(item: $sheet, onDismiss: presentPendingResolve) { which in
            switch which {
            case .open:
                OpenRoundView(game: game)
            case .picks:
                if let round = openRound { PicksEntryView(game: game, round: round) }
            case .results:
                if let round = openRound {
                    ResultsEntryView(game: game, round: round, pendingResolve: $pendingResolve)
                }
            case .declare:
                DeclareWinnersView(game: game) {}
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
            }
        }
        // Tie resolution at the top level — presented only after the Results sheet
        // has fully dismissed, so two sheets never dismiss at once (which blanked
        // the screen). The manual "Resolve Round" button presents it the same way.
        .sheet(isPresented: $showResolve, onDismiss: presentPendingAutoOpen) {
            TieResolutionView(game: game, tiedPlayers: lastRoundTied) { followUp in
                pendingAutoOpen = followUp
            }
        }
        .sheet(item: $autoOpenType) { type in
            OpenRoundView(game: game, roundType: type)
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
    }

    /// Remove a player who's dropped out (cascade deletes their picks).
    private func removePlayer(_ player: Player) {
        game.players.removeAll { $0.id == player.id }
        context.delete(player)
        pendingRemovePlayer = nil
    }

    /// After the Results sheet dismisses with everyone eliminated, present the
    /// tie resolution (top level — never stacked on Results).
    private func presentPendingResolve() {
        guard pendingResolve else { return }
        pendingResolve = false
        showResolve = true
    }

    /// After a resolution that reinstated players, open the follow-up round.
    private func presentPendingAutoOpen() {
        guard let type = pendingAutoOpen else { return }
        pendingAutoOpen = nil
        autoOpenType = type
    }

    private var infoSection: some View {
        Section {
            LabeledContent("Status", value: game.status.rawValue.capitalized)
            LabeledContent("Round", value: "\(currentRound?.roundNumber ?? 0)")
        }
    }

    @ViewBuilder
    private var roundSection: some View {
        Section("Round") {
            if game.status == .complete {
                let winners = game.players.filter { $0.status == .winner }
                LabeledContent(winners.count == 1 ? "Winner" : "Winners",
                               value: winners.map(\.name).joined(separator: ", "))
            } else if let round = openRound {
                LabeledContent("Round \(round.roundNumber)", value: round.status.rawValue.capitalized)
                Button { sheet = .picks } label: { Label("Enter Picks", systemImage: "checklist") }
                Button { sheet = .results } label: { Label("Enter Results / Close", systemImage: "flag.checkered") }
                    // Can't close a round with players still unassigned — finish
                    // the picks first (Auto-Assign handles any latecomers).
                    .disabled(!openRoundPicksComplete)
            } else if unresolvedTie {
                // Everyone went out together and the round was left unresolved —
                // let the manager finish resolving it so the game can continue.
                LabeledContent("Round \(latestClosedRound?.roundNumber ?? 0)", value: "No clear winner")
                Button { showResolve = true } label: {
                    Label("Resolve Round", systemImage: "exclamationmark.triangle")
                }
            } else {
                Button { sheet = .open } label: { Label("Open Round", systemImage: "calendar.badge.plus") }
                    .disabled(game.activePlayers.isEmpty)
            }

            if game.status != .complete {
                // Available only once a round has been played and at least one
                // player is still standing — nothing to declare before then.
                Button { sheet = .declare } label: {
                    Label("Declare Winner(s)…", systemImage: "trophy")
                }
                .disabled(latestClosedRound == nil || game.activePlayers.isEmpty)
            }
        }
    }

    @ViewBuilder
    private var summarySection: some View {
        if openRound != nil || latestClosedRound != nil || game.lastOutcome != nil {
            Section("Summary Cards") {
                // Gate the ad on opening the card — otherwise the rendered card is
                // on screen and users can screenshot it without watching the ad.
                Button { AdGate.run { sheet = .summaryPicks } } label: {
                    Label("Share Picks Card", systemImage: "square.and.arrow.up")
                }
                .disabled(!openRoundPicksComplete)

                Button { AdGate.run { sheet = .summaryResults } } label: {
                    Label("Share Results Card", systemImage: "square.and.arrow.up")
                }
                .disabled(latestClosedRound == nil)

                if let ending = game.lastOutcome {
                    Button { AdGate.run { sheet = .summaryOutcome } } label: {
                        Label("Share \(ending.headline) Card", systemImage: "square.and.arrow.up")
                    }
                    .disabled(latestClosedRound == nil)
                }
            }
        }
    }

    private var playersSection: some View {
        Section("Players (\(game.players.count))") {
            if game.players.isEmpty {
                Text("No players yet.").foregroundStyle(.secondary)
            } else {
                ForEach(sortedPlayers) { player in
                    HStack {
                        Text(player.name)
                        if player.isManager {
                            Text("you")
                                .font(.caption2).fontWeight(.semibold)
                                .foregroundStyle(.blue)
                        }
                        Spacer()
                        if player.status != .active {
                            Text(player.status.rawValue.capitalized)
                                .font(.caption)
                                .foregroundStyle(player.status == .winner ? .green : .red)
                        }
                    }
                    // Drop-out removal: swipe to reveal, then confirm — two
                    // deliberate steps so it can't happen by accident mid-game.
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) { pendingRemovePlayer = player } label: {
                            Label("Remove", systemImage: "person.fill.xmark")
                        }
                    }
                }
            }
            Button { showingAddPlayers = true } label: {
                Label("Add Players", systemImage: "person.badge.plus")
            }
        }
    }
}
