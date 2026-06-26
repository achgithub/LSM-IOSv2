import SwiftUI
import SwiftData

/// List of games this manager runs (local SwiftData). New Game FAB; the rewarded
/// ad gate for free users is added in a later phase.
struct GamesListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Game.createdAt, order: .reverse) private var games: [Game]
    @State private var showingNew = false
    @State private var showingWizard = false
    @State private var showingTutorial = false
    @State private var wizardGame: Game?

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
                        Button("New Game") { showingNew = true }
                        Button { showingTutorial = true } label: {
                            Label("See How It Works", systemImage: "play.circle")
                        }
                        .tint(.secondary)
                    }
                } else {
                    List {
                        ForEach(games) { game in
                            NavigationLink(value: game) { GameCard(game: game) }
                                // Swipe a game right to (re)open its guided wizard —
                                // it resumes at the game's current phase and loops on.
                                // LMS-only: the wizard's phases (picks/results/tie
                                // resolution) are built around Pick/elimination and
                                // have no Predictor equivalent yet.
                                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                    Button { wizardGame = game } label: {
                                        Label("Wizard", systemImage: "wand.and.stars")
                                    }
                                    .tint(.purple)
                                }
                        }
                        .onDelete(perform: delete)
                    }
                }
            }
            .appBackground()
            .navigationTitle("Games")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingWizard = true } label: { Image(systemName: "wand.and.stars") }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showingNew = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("New Game")
                }
            }
            .navigationDestination(for: Game.self) { game in
                switch game.mode {
                case .lms: GameDetailView(game: game)
                case .predictor: PredictorGameDetailView(game: game)
                }
            }
            .sheet(isPresented: $showingNew) { NewGameView() }
            .fullScreenCover(isPresented: $showingWizard) { GameWizardView() }
            .fullScreenCover(item: $wizardGame) { GameWizardView(game: $0) }
            .fullScreenCover(isPresented: $showingTutorial) { TutorialContainerView() }
        }
    }

    private func delete(_ offsets: IndexSet) {
        for index in offsets { context.delete(games[index]) }
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
        }
    }
}

private struct ModeBadge: View {
    let mode: GameMode
    var body: some View {
        Text(mode == .lms ? "LMS" : "Predictor")
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
