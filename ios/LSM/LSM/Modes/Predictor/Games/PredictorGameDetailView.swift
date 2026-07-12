import SwiftUI
import SwiftData

private enum PredictorSheet: String, Identifiable {
    case open, predictions, results, standings, publish, submissions
    case shareFixtures, shareEntryClosed, shareWeeklyResults, shareLeague, shareWinner
    var id: String { rawValue }
}

/// Predictor game detail: same shell as `GameDetailView` (info/roster) but
/// without any of the LMS-specific elimination/tie-resolution machinery —
/// every player just accumulates points round over round, indefinitely.
struct PredictorGameDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(Entitlements.self) private var entitlements

    @Bindable var game: Game
    @State private var showingAddPlayers = false
    @State private var sheet: PredictorSheet?
    @State private var pendingRemovePlayer: Player?
    @State private var pendingEditFixtures = false
    @State private var renaming = false
    @State private var renameText = ""

    @AppStorage("pwaSubmissionsEnabled") private var pwaSubmissionsEnabled = false
    @AppStorage(ManagerSettings.nameKey) private var managerName = ""

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

    var body: some View {
        List {
            infoSection
            roundSection
            shareSection
            playersSection
        }
        .navigationTitle(game.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    renameText = game.name
                    renaming = true
                } label: {
                    Label("Rename Game", systemImage: "pencil")
                }
            }
        }
        .alert("Rename game", isPresented: $renaming) {
            TextField("Game name", text: $renameText)
            Button("Rename") { commitRename() }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showingAddPlayers) { AddPlayersView(game: game) }
        .sheet(item: $sheet) { which in
            switch which {
            case .open:
                OpenRoundView(game: game)
            case .predictions:
                if let round = openRound { PredictionsEntryView(game: game, round: round) }
            case .results:
                if let round = openRound { PredictorResultsEntryView(game: game, round: round) }
            case .standings:
                NavigationStack { PredictorStandingsView(game: game) }
            case .publish:
                PublishPredictorView(game: game)
            case .submissions:
                if let round = openRound, let gameToken = game.cloudGameToken {
                    NavigationStack {
                        SubmissionQueueView(game: game, round: round, gameToken: gameToken)
                    }
                }
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

    private func shareCardButton(_ title: LocalizedStringKey, _ which: PredictorSheet, enabled: Bool) -> some View {
        Button { AdGate.run { sheet = which } } label: {
            Label(title, systemImage: "square.and.arrow.up")
        }
        .disabled(!enabled)
    }

    private var infoSection: some View {
        Section {
            LabeledContent("Status", value: game.status.label)
            LabeledContent("Matchday", value: "\(currentRound?.roundNumber ?? 0)")
            Button { sheet = .standings } label: {
                Label("Standings", systemImage: "list.number")
            }
            // Hidden for new use — Publish League's rough edges (issues #14,
            // #16, #17) aren't worth polishing right now. Left reachable only
            // for a game that already has a live published link, so an
            // existing manager can still get back in to unpublish/manage it
            // rather than being stranded with an orphaned public page.
            if entitlements.canUseCloud && game.predictorPublishLinkId != nil {
                Button { sheet = .publish } label: {
                    Label("Publish League…", systemImage: "globe")
                }
            }
            // Safety net for the auto push on round-open — re-sends current
            // fixtures/state plus the last round's results, always safe to
            // repeat (upserts, not appends).
            if entitlements.canUseCloud && pwaSubmissionsEnabled, game.cloudGameToken != nil {
                Button {
                    let name = managerName
                    Task { await PWARoundPusher.pushLMSOrPredictor(game: game, round: nil, managerName: name, context: context) }
                } label: {
                    Label("Resend to Player App", systemImage: "arrow.clockwise.icloud")
                }
            }
        }
    }

    @ViewBuilder
    private var roundSection: some View {
        Section("This Matchday") {
            if let round = openRound {
                LabeledContent("Matchday \(round.roundNumber)", value: round.status.label)
                Button(role: .destructive) { pendingEditFixtures = true } label: {
                    Label("Edit Fixtures", systemImage: "pencil")
                }
                Button { sheet = .predictions } label: { Label("Enter Predictions", systemImage: "checklist") }
                    .tutorialAnchor(id: "pred.enterPredictions")
                Button { sheet = .results } label: { Label("Enter Results / Close", systemImage: "flag.checkered") }
                    .tutorialAnchor(id: "pred.enterResults")
                if entitlements.canUseCloud && pwaSubmissionsEnabled, game.cloudGameToken != nil {
                    Button { sheet = .submissions } label: {
                        Label("Submission Queue", systemImage: "tray.and.arrow.down")
                    }
                }
                shareCardButton("Share Fixtures Card", .shareFixtures, enabled: true)
                shareCardButton("Share Entry Closed Card", .shareEntryClosed, enabled: round.status != .open)
            } else {
                Button { sheet = .open } label: { Label("Open Matchday", systemImage: "calendar.badge.plus") }
                    .disabled(game.players.isEmpty)
                    .tutorialAnchor(id: "pred.openRound")
            }
        }
    }

    @ViewBuilder
    private var shareSection: some View {
        if latestClosedRound != nil {
            Section("Share") {
                shareCardButton("Share Weekly Results", .shareWeeklyResults, enabled: true)
                    .tutorialAnchor(id: "pred.shareResults")
                shareCardButton("Share League Table", .shareLeague, enabled: true)
                shareCardButton("Share Final Standings", .shareWinner, enabled: true)
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
            .tutorialAnchor(id: "pred.addPlayers")
        }
    }

    private func removePlayer(_ player: Player) {
        game.players.removeAll { $0.id == player.id }
        context.delete(player)
        pendingRemovePlayer = nil
    }

    /// `game.name` is read live everywhere it's used (share cards, PWA
    /// pushes) rather than cached, so nothing else needs to change here.
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

}
