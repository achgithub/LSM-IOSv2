import SwiftUI
import SwiftData

/// Presented from `GamesPortalViewV2`'s Sync button and pull-to-refresh —
/// every path into `SyncCoordinator.sync` goes through here. Lists only
/// games with a currently open round (anything else has nothing to push,
/// same reasoning as `SyncCoordinator`'s `skippedNoOpenRound`), each with
/// its own checkbox, none pre-ticked and no "Select all" — a manager picks
/// games one at a time on purpose. Every push is a billed Worker
/// invocation, so this trades one extra tap for never fanning a sync out
/// across every running game by accident.
struct SyncGamePickerViewV2: View {
    let games: [Game]
    let onConfirm: (Set<UUID>) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<UUID> = []

    private var eligibleGames: [Game] {
        games.filter { game in game.rounds.contains { $0.status == .open } }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: V2Theme.Spacing.section) {
                    if eligibleGames.isEmpty {
                        Card(floating: true) {
                            Text("No games have an open round to push right now.")
                                .foregroundStyle(V2Theme.textSecondary)
                        }
                    } else {
                        VStack(spacing: 10) {
                            ForEach(eligibleGames) { game in
                                row(for: game)
                            }
                        }
                        Text("Only games with an open round can be synced. Pick which ones to push — each sync is a network call, so nothing is pre-selected.")
                            .font(.caption)
                            .foregroundStyle(V2Theme.textSecondary)
                    }
                }
                .padding(.horizontal, V2Theme.Spacing.horizontal)
                .padding(.vertical, V2Theme.Spacing.section)
                .padding(.bottom, 60)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .v2TrophyRoomScene()
            .v2FloatingHeader("Sync Games")
            .safeAreaInset(edge: .bottom) {
                Button {
                    onConfirm(selected)
                    dismiss()
                } label: {
                    Text(selected.isEmpty ? "Select games to sync" : "Sync \(selected.count) \(selected.count == 1 ? "Game" : "Games")")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .disabled(selected.isEmpty)
                .padding(.horizontal, V2Theme.Spacing.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 8)
                .background(.ultraThinMaterial)
            }
        }
    }

    @ViewBuilder
    private func row(for game: Game) -> some View {
        Button {
            if selected.contains(game.id) {
                selected.remove(game.id)
            } else {
                selected.insert(game.id)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: selected.contains(game.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected.contains(game.id) ? V2Theme.accent : V2Theme.textTertiary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(game.name)
                        .foregroundStyle(V2Theme.textPrimary)
                    Text(game.mode.displayName)
                        .font(.caption)
                        .foregroundStyle(V2Theme.textSecondary)
                }
                Spacer()
            }
            .padding(16)
            .v2FloatingCard()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
