import SwiftUI
import SwiftData

/// List of games this manager runs (local SwiftData). New Game FAB; the rewarded
/// ad gate for free users is added in a later phase.
struct GamesListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Game.createdAt, order: .reverse) private var games: [Game]
    @State private var showingNew = false
    @State private var showingWizard = false
    /// The game whose ongoing wizard is open (launched by swiping a row right).
    @State private var wizardGame: Game?
    /// Drives the "Show Me" demo and the auto-navigation to the demo game.
    @State private var demo = DemoWalkthroughManager.shared
    /// Navigation path so the demo can push (and pop) the demo game's detail view
    /// automatically as the walkthrough starts and ends.
    @State private var path: [Game] = []

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if games.isEmpty {
                    ContentUnavailableView {
                        Label("No games yet", systemImage: "trophy")
                    } description: {
                        Text("Create your first Last Man Standing game.")
                    } actions: {
                        Button("Guided Setup") { showingWizard = true }
                            .buttonStyle(.borderedProminent)
                        Button("New Game") { showingNew = true }
                        // Interactive product tour: builds a full game step by
                        // step with sample data (ad-free, cleared on exit).
                        Button {
                            demo.start(context: context)
                        } label: {
                            Label("Show Me", systemImage: "wand.and.stars")
                        }
                    }
                } else {
                    List {
                        ForEach(games) { game in
                            NavigationLink(value: game) { GameCard(game: game) }
                                // Swipe a game right to (re)open its guided wizard —
                                // it resumes at the game's current phase and loops on.
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
                }
            }
            .navigationDestination(for: Game.self) { GameDetailView(game: $0) }
            .sheet(isPresented: $showingNew) { NewGameView() }
            .fullScreenCover(isPresented: $showingWizard) { GameWizardView() }
            .fullScreenCover(item: $wizardGame) { GameWizardView(game: $0) }
        }
        // Follow the demo: push the demo game when the walkthrough creates it (so
        // the user watches it build on the real detail screen), and pop back when
        // the demo ends.
        .onChange(of: demo.demoGameID) { _, id in syncDemoNavigation(id) }
        // The new demo game may not be in `games` the instant `demoGameID` is set
        // (the @Query refreshes a beat later) — re-run when the list changes so
        // the push still lands.
        .onChange(of: games.count) { _, _ in syncDemoNavigation(demo.demoGameID) }
        .onAppear { syncDemoNavigation(demo.demoGameID) }
    }

    /// Drive the navigation path from the demo's current game id.
    private func syncDemoNavigation(_ id: UUID?) {
        guard let id else {
            // Demo ended/cleared — return to the list.
            if !path.isEmpty { path.removeAll() }
            return
        }
        // Game id is set but not in `games` yet — wait for the @Query refresh
        // (handled by the games-count change), don't clear the path.
        guard let game = games.first(where: { $0.id == id }) else { return }
        if path.last?.id != game.id { path = [game] }
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
                Spacer()
                StatusBadge(status: game.status)
            }
            HStack(spacing: 12) {
                Label("Round \(game.currentRound?.roundNumber ?? 0)", systemImage: "calendar")
                Label("\(game.activePlayers.count) active", systemImage: "person.fill")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
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
