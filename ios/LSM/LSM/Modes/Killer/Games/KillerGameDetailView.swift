import SwiftUI
import SwiftData

private enum KillerSheet: String, Identifiable {
    case open, predictions, results, scratchpad, submissions
    case shareFixtures, sharePlayerKey, shareWeeklyResults, shareStandings, shareWinner
    var id: String { rawValue }
}

/// Killer game detail: same shell shape as `PredictorGameDetailView` (info/
/// round/players) plus a lives leaderboard, the end-of-game tiebreak
/// surface, and share cards / scratchpad text entry.
struct KillerGameDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(Entitlements.self) private var entitlements
    @Bindable var game: Game
    @State private var showingAddPlayers = false
    @State private var sheet: KillerSheet?
    @State private var pendingRemovePlayer: Player?

    @AppStorage("pwaSubmissionsEnabled") private var pwaSubmissionsEnabled = false
    @AppStorage(ManagerSettings.nameKey) private var managerName = ""
    /// Set by `KillerResultsEntryView` when closing produces a `.stillTied`
    /// outcome; presented at the top level (after that sheet dismisses)
    /// rather than stacking a sheet on a sheet.
    @State private var pendingTiebreakIds: [UUID]?

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

    var body: some View {
        List {
            infoSection
            roundSection
            shareSection
            livesSection
            playersSection
        }
        .navigationTitle(game.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingAddPlayers) { AddPlayersView(game: game) }
        .sheet(item: $sheet) { which in
            switch which {
            case .open:
                KillerOpenRoundView(game: game)
            case .predictions:
                if let round = openRound { KillerPredictionsEntryView(game: game, round: round) }
            case .results:
                if let round = openRound {
                    KillerResultsEntryView(game: game, round: round, pendingTiebreakIds: $pendingTiebreakIds)
                }
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
        .sheet(isPresented: Binding(
            get: { pendingTiebreakIds != nil },
            set: { if !$0 { pendingTiebreakIds = nil } }
        )) {
            if let ids = pendingTiebreakIds {
                KillerTiebreakView(game: game, candidates: game.players.filter { ids.contains($0.id) })
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

    private func shareCardButton(_ title: LocalizedStringKey, _ which: KillerSheet, enabled: Bool) -> some View {
        Button { AdGate.run { sheet = which } } label: {
            Label(title, systemImage: "square.and.arrow.up")
        }
        .disabled(!enabled)
    }

    private var infoSection: some View {
        Section {
            LabeledContent("Status", value: game.status.label)
            LabeledContent("Round", value: "\(currentRound?.roundNumber ?? 0)")
            if let currentPhase {
                LabeledContent("Phase", value: currentPhase == .build ? "Build" : "Kill")
            }
            // Safety net for the auto pushes (round-open, game-complete) —
            // re-sends current fixtures/state plus the last round's results,
            // always safe to repeat (upserts, not appends).
            if entitlements.canUseCloud && pwaSubmissionsEnabled, game.cloudGameToken != nil {
                Button {
                    let name = managerName
                    Task { await PWARoundPusher.pushKiller(game: game, round: nil, managerName: name, context: context) }
                } label: {
                    Label("Resend to Player App", systemImage: "arrow.clockwise.icloud")
                }
            }
        }
    }

    @ViewBuilder
    private var roundSection: some View {
        Section("This Round") {
            if let round = openRound {
                LabeledContent("Round \(round.roundNumber)", value: round.status.label)
                Button { sheet = .predictions } label: { Label("Enter Predictions", systemImage: "checklist") }
                Button { sheet = .scratchpad } label: { Label("Scratchpad (Paste Picks)", systemImage: "text.badge.plus") }
                Button { sheet = .results } label: { Label("Enter Results / Close", systemImage: "flag.checkered") }
                shareCardButton("Share Fixtures Card", .shareFixtures, enabled: true)
                if currentPhase == .kill {
                    shareCardButton("Share Player Key Card", .sharePlayerKey, enabled: true)
                }
                if entitlements.canUseCloud && pwaSubmissionsEnabled, game.cloudGameToken != nil {
                    Button { sheet = .submissions } label: {
                        Label("Submission Queue", systemImage: "tray.and.arrow.down")
                    }
                }
            } else {
                Button { sheet = .open } label: { Label("Open Round", systemImage: "calendar.badge.plus") }
                    .disabled(game.players.isEmpty)
            }
        }
    }

    @ViewBuilder
    private var shareSection: some View {
        if latestClosedRound != nil {
            Section("Share") {
                shareCardButton("Share Weekly Results", .shareWeeklyResults, enabled: true)
                shareCardButton("Share Accuracy Table", .shareStandings, enabled: true)
                if game.status == .complete {
                    shareCardButton("Share Final Result", .shareWinner, enabled: true)
                }
            }
        }
    }

    private var livesSection: some View {
        Section("Lives") {
            if game.players.isEmpty {
                Text("No players yet.").foregroundStyle(.secondary)
            } else {
                ForEach(sortedByLives) { player in
                    HStack {
                        Text(player.name)
                        if player.status == .eliminated {
                            Text("eliminated").font(.caption2).foregroundStyle(.secondary)
                        } else if pendingTiebreakIds?.contains(player.id) == true {
                            Text("tie pending").font(.caption2).foregroundStyle(.orange)
                        }
                        Spacer()
                        Text(String(repeating: "❤️", count: max(0, player.killerState?.lives ?? 0)))
                            .font(.caption)
                    }
                }
            }
        }
    }

    private var playersSection: some View {
        Section("Players (\(game.players.count))") {
            if game.players.isEmpty {
                Text("No players yet.").foregroundStyle(.secondary)
            } else {
                ForEach(game.players.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) { player in
                    HStack {
                        Text(player.name)
                        if player.isManager {
                            Text("you")
                                .font(.caption2).fontWeight(.semibold)
                                .foregroundStyle(.blue)
                        }
                        Spacer()
                    }
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

    private func removePlayer(_ player: Player) {
        game.players.removeAll { $0.id == player.id }
        context.delete(player)
        pendingRemovePlayer = nil
    }
}
