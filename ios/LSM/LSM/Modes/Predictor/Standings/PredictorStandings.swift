import Foundation

/// One player's row in the on-device Predictor league table.
struct PredictorStandingRow: Identifiable {
    let player: Player
    let points: Int
    /// Standard competition ranking ("1, 1, 3") — ties share a position.
    let position: Int
    var id: UUID { player.id }
}

/// Local aggregation of a Predictor game's standings — no cloud involved.
/// Three render targets (on-device table, share-card, published page) all
/// derive from this same shape per §0; Phase 1 only builds the on-device one.
enum PredictorStandings {
    /// Total points per player across every closed round's predictions,
    /// ranked by points only (no secondary tiebreakers), ties alphabetical.
    static func rows(for game: Game) -> [PredictorStandingRow] {
        let totals = game.players.map { player -> (Player, Int) in
            let points = player.predictions
                .filter { $0.round?.status == .closed }
                .compactMap(\.pointsAwarded)
                .reduce(0, +)
            return (player, points)
        }
        let sorted = totals.sorted { a, b in
            if a.1 != b.1 { return a.1 > b.1 }
            return a.0.name.localizedCaseInsensitiveCompare(b.0.name) == .orderedAscending
        }

        var rows: [PredictorStandingRow] = []
        var position = 0
        var lastPoints: Int?
        for (index, entry) in sorted.enumerated() {
            if entry.1 != lastPoints {
                position = index + 1
                lastPoints = entry.1
            }
            rows.append(PredictorStandingRow(player: entry.0, points: entry.1, position: position))
        }
        return rows
    }

    /// The current leader's name, for the home-screen GameCard secondary line.
    /// nil if no rounds have closed yet.
    static func leaderName(for game: Game) -> String? {
        let ranked = rows(for: game)
        guard let top = ranked.first, top.points > 0 else { return nil }
        return top.player.name
    }
}
