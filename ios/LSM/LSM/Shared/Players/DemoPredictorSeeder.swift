import Foundation
import SwiftData

#if DEBUG
/// DEBUG-only convenience: seeds one Predictor game with several CLOSED
/// matchdays already scored, so there's something to look at immediately —
/// a multi-week standings table, recent results, a Publish/Backup test
/// subject — without manually running rounds for weeks first. Never
/// compiled into a Release/TestFlight/App Store build.
///
/// One-time via a UserDefaults flag, same pattern as `DemoRosterSeeder` (and
/// independent of it — this seeds its own players directly on the demo game
/// rather than depending on the roster).
enum DemoPredictorSeeder {
    private static let seededKey = "debugDidSeedDemoPredictorGame"
    private static let matchdayCount = 4
    private static let fixturesPerMatchday = 3
    private static let playerNames = (1...10).map { "Demo Player \($0)" }

    static func seedIfNeeded(context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: seededKey) else { return }
        UserDefaults.standard.set(true, forKey: seededKey)

        let game = Game(
            name: "Demo Predictor League",
            season: Leagues.app.season,
            allowRepeats: true,
            mode: .predictor
        )
        context.insert(game)
        game.status = .active

        let players = playerNames.map { Player(name: $0, game: game) }
        players.forEach { context.insert($0); game.players.append($0) }

        var rng = SystemRandomNumberGenerator()
        for matchday in 1...matchdayCount {
            let fixtureIds = (1...fixturesPerMatchday).map { matchday * 100 + $0 }
            let round = Round(roundNumber: matchday, deadline: .now, fixtureIds: fixtureIds, game: game)
            round.statusRaw = RoundStatus.closed.rawValue
            context.insert(round)
            game.rounds.append(round)

            // One real final score per fixture, shared by every player's prediction.
            let actuals = Dictionary(uniqueKeysWithValues: fixtureIds.map { fixtureId in
                (fixtureId, (home: Int.random(in: 0...4, using: &rng), away: Int.random(in: 0...4, using: &rng)))
            })

            for player in players {
                for fixtureId in fixtureIds {
                    guard let actual = actuals[fixtureId] else { continue }
                    // A spread of prediction accuracy across players/weeks —
                    // some exact, some close, some wrong — so standings end up
                    // with realistic separation rather than a flat tie.
                    let (predictedHome, predictedAway) = Self.predictedScore(near: actual, using: &rng)
                    let prediction = Prediction(
                        fixtureId: fixtureId, predictedHome: predictedHome, predictedAway: predictedAway,
                        player: player, round: round
                    )
                    prediction.actualHome = actual.home
                    prediction.actualAway = actual.away
                    prediction.pointsAwarded = PredictorScoringService.score(
                        predictedHome: predictedHome, predictedAway: predictedAway,
                        actualHome: actual.home, actualAway: actual.away, game: game
                    )
                    context.insert(prediction)
                    round.predictions.append(prediction)
                }
            }
        }

        // Next matchday, still open, so there's something to publish as "upcoming".
        let nextRound = Round(
            roundNumber: matchdayCount + 1, deadline: .now.addingTimeInterval(3 * 24 * 3600),
            fixtureIds: [(matchdayCount + 1) * 100 + 1, (matchdayCount + 1) * 100 + 2],
            game: game
        )
        context.insert(nextRound)
        game.rounds.append(nextRound)
    }

    /// A prediction near the actual score, with a random miss distance so
    /// results land across every scoring rung (exact/GD/result/wrong).
    private static func predictedScore(
        near actual: (home: Int, away: Int), using rng: inout SystemRandomNumberGenerator
    ) -> (Int, Int) {
        switch Int.random(in: 0...3, using: &rng) {
        case 0: return actual // exact
        case 1: return (max(0, actual.home + 1), actual.away) // same GD-ish, off by one
        case 2: return (actual.away, actual.home) // plausible but usually wrong result
        default: return (Int.random(in: 0...4, using: &rng), Int.random(in: 0...4, using: &rng)) // wild guess
        }
    }
}
#endif
