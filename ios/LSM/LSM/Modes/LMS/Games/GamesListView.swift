import SwiftUI
import SwiftData

/// List of games this manager runs (local SwiftData). New Game FAB; the rewarded
/// ad gate for free users is added in a later phase.
struct GamesListView: View {
    @Environment(\.modelContext) private var context
    @Environment(Entitlements.self) private var entitlements
    @Query(sort: \Game.createdAt, order: .reverse) private var games: [Game]
    @State private var showingNew = false
    @State private var showingWizard = false
    @State private var showingTutorial = false
    @State private var showingGameLimit = false
    @State private var wizardGame: Game?
    @State private var pendingDeleteOffsets: IndexSet?

    private var activeGameCount: Int {
        games.filter { $0.status != .complete }.count
    }

    private var atGameLimit: Bool {
        activeGameCount >= entitlements.maxActiveGames
    }

    var body: some View {
        NavigationStack {
            Group {
                if games.isEmpty {
                    ContentUnavailableView {
                        Label("No games yet", systemImage: "trophy")
                    } description: {
                        Text("Create your first game.")
                    } actions: {
                        Button { showingWizard = true } label: {
                            Label("Guided Setup", systemImage: "wand.and.stars")
                        }
                        .buttonStyle(.borderedProminent)
                        Button("New Game") {
                            if atGameLimit { showingGameLimit = true } else { showingNew = true }
                        }
                        // Commented out, not deleted — the "Show Me" tutorial
                        // walkthrough isn't good enough yet; revisit in the
                        // future rather than polish it now that the guided
                        // wizard exists as the primary on-ramp.
                        // Button { showingTutorial = true } label: {
                        //     Label("See How It Works", systemImage: "play.circle")
                        // }
                        // .tint(.secondary)
                    }
                } else {
                    List {
                        ForEach(games) { game in
                            NavigationLink(value: game) { GameCard(game: game) }
                                // Swipe a game right to (re)open its guided wizard —
                                // it resumes at the game's current phase and loops on,
                                // for all three modes.
                                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                    Button { wizardGame = game } label: {
                                        Label("Wizard", systemImage: "wand.and.stars")
                                    }
                                    .tint(.purple)
                                }
                        }
                        .onDelete { pendingDeleteOffsets = $0 }
                    }
                }
            }
            .appBackground()
            .navigationTitle("Games")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingWizard = true } label: { Image(systemName: "wand.and.stars") }
                        .accessibilityLabel("Guided Setup")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        if atGameLimit { showingGameLimit = true } else { showingNew = true }
                    } label: { Image(systemName: "plus") }
                        .accessibilityLabel("New Game")
                }
            }
            .navigationDestination(for: Game.self) { game in
                switch game.mode {
                case .lms: GameDetailView(game: game)
                case .predictor: PredictorGameDetailView(game: game)
                case .killer: KillerGameDetailView(game: game)
                }
            }
            .sheet(isPresented: $showingNew) { NewGameView() }
            .alert("Game limit reached", isPresented: $showingGameLimit) {
                Button("OK", role: .cancel) {}
            } message: {
                let limit = entitlements.maxActiveGames
                Text("Your \(entitlements.tier.label) plan includes \(limit) active games. Complete an existing game or upgrade to run more.")
            }
            .fullScreenCover(isPresented: $showingWizard) { GameWizardView() }
            .fullScreenCover(item: $wizardGame) { GameWizardView(game: $0) }
            .fullScreenCover(isPresented: $showingTutorial) { TutorialContainerView() }
            .confirmationDialog(
                deleteTitle,
                isPresented: Binding(get: { pendingDeleteOffsets != nil }, set: { if !$0 { pendingDeleteOffsets = nil } }),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) { confirmDelete() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(deleteMessage)
            }
        }
    }

    private var deleteTitle: String {
        (pendingDeleteOffsets?.count ?? 1) == 1 ? "Delete this game?" : "Delete \(pendingDeleteOffsets?.count ?? 0) games?"
    }

    private var deleteMessage: String {
        (pendingDeleteOffsets?.count ?? 1) == 1
            ? "This permanently deletes the game and its history — on this device and in the cloud, including any player picks or predictions submitted through their links."
            : "This permanently deletes these games and their history — on this device and in the cloud, including any player picks or predictions submitted through their links."
    }

    private func confirmDelete() {
        guard let offsets = pendingDeleteOffsets else { return }
        for index in offsets { GameLogicService.deleteGame(games[index], context: context) }
        pendingDeleteOffsets = nil
    }
}

private struct GameCard: View {
    let game: Game

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(game.name).font(.headline)
                ModeBadge(mode: game.mode)
                Spacer()
                StatusBadge(status: game.status)
            }
            secondaryLine
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var secondaryLine: some View {
        switch game.mode {
        case .lms:
            HStack(spacing: 12) {
                Label("Round \(game.currentRound?.roundNumber ?? 0)", systemImage: "calendar")
                Label("\(game.activePlayers.count) active", systemImage: "person.fill")
            }
        case .predictor:
            HStack(spacing: 12) {
                Label("Matchday \(game.currentRound?.roundNumber ?? 0)", systemImage: "calendar")
                Label("\(game.players.count) players", systemImage: "person.fill")
                if let leader = PredictorStandings.leaderName(for: game) {
                    Label(leader, systemImage: "crown.fill")
                }
            }
        case .killer:
            HStack(spacing: 12) {
                Label("Round \(game.currentRound?.roundNumber ?? 0)", systemImage: "calendar")
                Label("\(game.activePlayers.count) active", systemImage: "person.fill")
            }
        }
    }
}

private struct ModeBadge: View {
    let mode: GameMode
    private var label: String {
        switch mode {
        case .lms: return "LMS"
        case .predictor: return "Predictor"
        case .killer: return "Killer"
        }
    }
    var body: some View {
        Text(label)
            .font(.caption2.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.blue.opacity(0.15), in: Capsule())
            .foregroundStyle(.blue)
    }
}

private struct StatusBadge: View {
    let status: GameStatus
    var body: some View {
        Text(status.label)
            .font(.caption2.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.2), in: Capsule())
            .foregroundStyle(color)
    }
    private var color: Color {
        switch status {
        case .setup: return .orange
        case .active: return .green
        case .complete: return .gray
        }
    }
}
