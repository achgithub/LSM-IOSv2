import SwiftUI

/// Card restyle survivors list — reached via a "Standings" link in
/// `GameDetailViewV2`'s info card, mirroring exactly how
/// `PredictorGameDetailViewV2`/`KillerGameDetailViewV2` link out to their own
/// standalone summary screens rather than showing an inline list. LMS has no
/// points/lives to rank by, so the equivalent summary is survival: active
/// players first, then eliminated players below a divider with the round
/// they went out.
struct LMSStandingsViewV2: View {
    let game: Game

    private var activePlayers: [Player] {
        let notEliminated = game.players.filter { $0.status != .eliminated }
        return notEliminated.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var eliminatedPlayers: [(player: Player, roundOut: Int?)] {
        let eliminated: [Player] = game.players.filter { $0.status == .eliminated }
        let entries: [(player: Player, roundOut: Int?)] = eliminated.map { player in
            (player: player, roundOut: roundEliminated(player))
        }
        return entries.sorted { lhs, rhs in
            (lhs.roundOut ?? 0) > (rhs.roundOut ?? 0)
        }
    }

    /// Matches `GameEngine.computeEliminations`'s own rule for which pick
    /// results actually eliminate a player — not just `.loss`, but `.draw`/
    /// `.postponed` too when the game's toggles make them eliminating.
    /// Missing either meant a draw/postponed elimination showed as generic
    /// "out" with no round number. Rounds are sorted by `roundNumber` before
    /// searching since `game.rounds` (a SwiftData relationship) isn't
    /// guaranteed to already be in round order.
    private func roundEliminated(_ player: Player) -> Int? {
        game.rounds
            .filter { $0.status == .closed }
            .sorted { $0.roundNumber < $1.roundNumber }
            .first { round in
                round.picks.contains { pick in
                    guard pick.player?.id == player.id else { return false }
                    switch pick.result {
                    case .loss: return true
                    case .draw: return game.drawEliminates
                    case .postponed: return game.postponedEliminates
                    case .win, .none: return false
                    }
                }
            }?.roundNumber
    }

    var body: some View {
        NavigationStack {
            Group {
                if game.players.isEmpty {
                    ContentUnavailableView("No players yet", systemImage: "person.3")
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(activePlayers) { player in
                                LMSStandingsRowV2(player: player, roundOut: nil)
                            }
                            if !eliminatedPlayers.isEmpty {
                                Divider().padding(.vertical, 4)
                                ForEach(eliminatedPlayers, id: \.player.id) { entry in
                                    LMSStandingsRowV2(player: entry.player, roundOut: entry.roundOut)
                                }
                            }
                        }
                        .padding(.horizontal, V2Theme.Spacing.horizontal)
                        .padding(.vertical, V2Theme.Spacing.section)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .v2LMSFormScene()
            .v2FloatingHeader("Standings")
        }
    }
}

private struct LMSStandingsRowV2: View {
    let player: Player
    let roundOut: Int?

    var body: some View {
        Card(padding: 16, floating: true) {
            HStack(spacing: 14) {
                Text(player.name)
                    .font(V2Theme.Typography.rowTitle)
                    .foregroundStyle(V2Theme.textPrimary)
                    .lineLimit(1)
                if player.isManager {
                    V2StatusBadge(label: "you", tint: V2Theme.Mode.lms)
                }
                Spacer(minLength: 8)
                if player.status == .winner {
                    Text("winner")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(V2Theme.accent)
                } else if let roundOut {
                    Text("out · Rd \(roundOut)")
                        .font(.caption)
                        .foregroundStyle(V2Theme.textTertiary)
                } else if player.status == .eliminated {
                    Text("out")
                        .font(.caption)
                        .foregroundStyle(V2Theme.textTertiary)
                } else {
                    Text("active")
                        .font(.caption)
                        .foregroundStyle(V2Theme.textSecondary)
                }
            }
        }
    }
}
