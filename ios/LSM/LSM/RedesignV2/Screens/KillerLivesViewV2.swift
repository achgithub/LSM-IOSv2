import SwiftUI

/// Card restyle of Killer's lives leaderboard — reached via a "Lives" link
/// in `KillerGameDetailViewV2`'s info card, mirroring exactly how
/// `PredictorGameDetailViewV2` links out to `PredictorStandingsViewV2`
/// rather than showing an inline list.
struct KillerLivesViewV2: View {
    let game: Game

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

    var body: some View {
        NavigationStack {
            Group {
                if sortedByLives.isEmpty {
                    ContentUnavailableView("No players yet", systemImage: "person.3")
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(sortedByLives) { player in
                                KillerLivesRowV2(player: player)
                            }
                        }
                        .padding(.horizontal, V2Theme.Spacing.horizontal)
                        .padding(.vertical, V2Theme.Spacing.section)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .v2TrophyRoomScene()
            .v2FloatingHeader("Lives")
        }
    }
}

private struct KillerLivesRowV2: View {
    let player: Player

    var body: some View {
        Card(padding: 16, floating: true) {
            HStack(spacing: 14) {
                Text(player.name)
                    .font(V2Theme.Typography.rowTitle)
                    .foregroundStyle(V2Theme.textPrimary)
                    .lineLimit(1)
                if player.isManager {
                    V2StatusBadge(label: "you", tint: V2Theme.Mode.killer)
                }
                if player.status == .eliminated {
                    Text("eliminated")
                        .font(.caption2)
                        .foregroundStyle(V2Theme.textTertiary)
                }
                Spacer(minLength: 8)
                Text(String(repeating: "❤️", count: max(0, player.killerState?.lives ?? 0)))
                    .font(.caption)
            }
        }
    }
}
