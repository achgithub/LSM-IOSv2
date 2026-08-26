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
/// Two render targets (on-device table, share-card) derive from this same
/// shape per §0.
enum PredictorStandings {
    /// Total points per player across every closed round's predictions,
    /// ranked by points only (no secondary tiebreakers), ties alphabetical.
    /// Includes `carriedOverPoints` — normally 0, only ever set by
    /// `GameSyncBuilder` for a game synced to a new device, where pre-sync
    /// history isn't available as real `Prediction` rows to sum.
    static func rows(for game: Game) -> [PredictorStandingRow] {
        let totals = game.players.map { player -> (Player, Int) in
            let points = player.predictions
                .filter { $0.round?.status == .closed }
                .compactMap(\.pointsAwarded)
                .reduce(0, +)
            return (player, points + player.carriedOverPoints)
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

    /// The single round's top scorer — points from that round alone, not the
    /// cumulative table `rows`/`leaderName` use — for Home's Favourites card
    /// "Last week" stat. nil if nobody scored any points in that round (e.g.
    /// it hasn't been scored yet, or every prediction missed).
    static func roundWinnerName(for game: Game, in round: Round) -> String? {
        let totals = game.players.map { player -> (Player, Int) in
            let points = player.predictions
                .filter { $0.round?.id == round.id }
                .compactMap(\.pointsAwarded)
                .reduce(0, +)
            return (player, points)
        }
        let sorted = totals.sorted { a, b in
            if a.1 != b.1 { return a.1 > b.1 }
            return a.0.name.localizedCaseInsensitiveCompare(b.0.name) == .orderedAscending
        }
        guard let top = sorted.first, top.1 > 0 else { return nil }
        return top.0.name
    }
}
