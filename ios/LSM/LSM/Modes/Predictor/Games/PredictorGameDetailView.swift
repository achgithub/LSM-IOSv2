import SwiftUI
import SwiftData

private enum PredictorSheet: String, Identifiable {
    case open, predictions, results, standings
    var id: String { rawValue }
}

/// Predictor game detail: same shell as `GameDetailView` (info/roster) but
/// without any of the LMS-specific elimination/tie-resolution machinery —
/// every player just accumulates points round over round, indefinitely.
struct PredictorGameDetailView: View {
    @Environment(\.modelContext) private var context
    @Bindable var game: Game
    @State private var showingAddPlayers = false
    @State private var sheet: PredictorSheet?
    @State private var pendingRemovePlayer: Player?
    @State private var pendingEditFixtures = false

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
            playersSection
        }
        .navigationTitle(game.name)
        .navigationBarTitleDisplayMode(.inline)
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

    private var infoSection: some View {
        Section {
            LabeledContent("Status", value: game.status.label)
            LabeledContent("Matchday", value: "\(currentRound?.roundNumber ?? 0)")
            Button { sheet = .standings } label: {
                Label("Standings", systemImage: "list.number")
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
                Button { sheet = .results } label: { Label("Enter Results / Close", systemImage: "flag.checkered") }
            } else {
                Button { sheet = .open } label: { Label("Open Matchday", systemImage: "calendar.badge.plus") }
                    .disabled(game.players.isEmpty)
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

    private func resetOpenRound() {
        guard let round = openRound else { return }
        game.rounds.removeAll { $0.id == round.id }
        context.delete(round)
    }
}
