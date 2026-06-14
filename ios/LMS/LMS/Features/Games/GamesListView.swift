import SwiftUI
import SwiftData

/// List of games this manager runs (local SwiftData). New Game FAB; the rewarded
/// ad gate for free users is added in a later phase.
struct GamesListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Game.createdAt, order: .reverse) private var games: [Game]
    @State private var showingNew = false

    var body: some View {
        NavigationStack {
            Group {
                if games.isEmpty {
                    ContentUnavailableView {
                        Label("No games yet", systemImage: "trophy")
                    } description: {
                        Text("Create your first Last Man Standing game.")
                    } actions: {
                        Button("New Game") { showingNew = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        ForEach(games) { game in
                            NavigationLink(value: game) { GameCard(game: game) }
                        }
                        .onDelete(perform: delete)
                    }
                }
            }
            .navigationTitle("Games")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingNew = true } label: { Image(systemName: "plus") }
                }
            }
            .navigationDestination(for: Game.self) { GameDetailView(game: $0) }
            .sheet(isPresented: $showingNew) { NewGameView() }
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
        Text(status.rawValue.capitalized)
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
