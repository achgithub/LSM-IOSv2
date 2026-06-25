import Testing
import Foundation
import SwiftData
@testable import LSM

/// Round-trip coverage for Cloud Backup's snapshot shape (§0): serialize a
/// live `Game` → `GameSnapshot` → JSON → back → fresh SwiftData rows, for
/// both LMS and Predictor games, confirming nothing is lost and restore never
/// collides with the original ids (mints fresh ones throughout).
struct GameSnapshotTests {

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Game.self, Player.self, Round.self, Pick.self, Prediction.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    @Test func lmsGameRoundTripsThroughJSON() throws {
        let context = try makeContext()
        let game = Game(name: "LMS Game", season: "2025/26", allowRepeats: false, mode: .lms)
        context.insert(game)
        let alice = Player(name: "Alice", game: game, entryNumber: 1)
        let bob = Player(name: "Bob", game: game, entryNumber: 2)
        context.insert(alice)
        context.insert(bob)
        game.players = [alice, bob]

        let round = Round(roundNumber: 1, deadline: .now, fixtureIds: [10, 11], game: game)
        context.insert(round)
        game.rounds = [round]
        let pickA = Pick(teamId: 100, player: alice, round: round)
        pickA.result = .win
        let pickB = Pick(teamId: 200, player: bob, round: round)
        pickB.result = .loss
        context.insert(pickA)
        context.insert(pickB)
        round.picks = [pickA, pickB]

        let snapshot = GameSnapshotBuilder.snapshot(of: game)
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(GameSnapshot.self, from: data)

        #expect(decoded.name == "LMS Game")
        #expect(decoded.modeRaw == GameMode.lms.rawValue)
        #expect(decoded.players.count == 2)
        #expect(decoded.rounds.count == 1)
        #expect(decoded.rounds[0].picks.count == 2)
        #expect(decoded.rounds[0].picks.contains { $0.teamId == 100 && $0.resultRaw == PickResult.win.rawValue })

        let restoreContext = try makeContext()
        let restored = GameSnapshotBuilder.restore(decoded, into: restoreContext)

        #expect(restored.id != game.id) // restore mints a fresh id, never reuses the original
        #expect(restored.name == "LMS Game")
        #expect(restored.mode == .lms)
        #expect(restored.players.count == 2)
        #expect(restored.rounds.count == 1)
        #expect(restored.rounds[0].picks.count == 2)
        let restoredAlice = restored.players.first { $0.name == "Alice" }
        #expect(restoredAlice?.id != alice.id)
        #expect(restored.rounds[0].picks.first { $0.teamId == 100 }?.player?.id == restoredAlice?.id)
    }

    @Test func predictorGameRoundTripsWithScoresAndJoker() throws {
        let context = try makeContext()
        let game = Game(
            name: "Predictor Game", season: "2025/26", allowRepeats: true,
            mode: .predictor, predictorJokerEnabled: true
        )
        context.insert(game)
        let alice = Player(name: "Alice", game: game, entryNumber: 1)
        context.insert(alice)
        game.players = [alice]

        let round = Round(roundNumber: 1, deadline: .now, fixtureIds: [101], game: game)
        round.statusRaw = RoundStatus.closed.rawValue
        context.insert(round)
        game.rounds = [round]

        let prediction = Prediction(
            fixtureId: 101, predictedHome: 2, predictedAway: 1, isJoker: true, player: alice, round: round
        )
        prediction.actualHome = 2
        prediction.actualAway = 1
        prediction.pointsAwarded = 8
        context.insert(prediction)
        round.predictions = [prediction]

        let snapshot = GameSnapshotBuilder.snapshot(of: game)
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(GameSnapshot.self, from: data)

        #expect(decoded.modeRaw == GameMode.predictor.rawValue)
        #expect(decoded.predictorJokerEnabled)
        #expect(decoded.rounds[0].predictions.count == 1)
        let pred = decoded.rounds[0].predictions[0]
        #expect(pred.isJoker)
        #expect(pred.pointsAwarded == 8)
        #expect(pred.actualHome == 2 && pred.actualAway == 1)

        let restoreContext = try makeContext()
        let restored = GameSnapshotBuilder.restore(decoded, into: restoreContext)

        #expect(restored.mode == .predictor)
        #expect(restored.predictorJokerEnabled)
        #expect(restored.rounds[0].predictions.count == 1)
        let restoredPrediction = restored.rounds[0].predictions[0]
        #expect(restoredPrediction.pointsAwarded == 8)
        #expect(restoredPrediction.isJoker)
        #expect(restoredPrediction.player?.name == "Alice")
    }

    @Test func backupBundleHoldsBothModesTogether() throws {
        let context = try makeContext()
        let lms = Game(name: "LMS", season: "2025/26", allowRepeats: false, mode: .lms)
        let predictor = Game(name: "Predictor", season: "2025/26", allowRepeats: true, mode: .predictor)
        context.insert(lms)
        context.insert(predictor)

        let bundle = BackupBundle(games: [lms, predictor].map(GameSnapshotBuilder.snapshot(of:)))
        let data = try JSONEncoder().encode(bundle)
        let decoded = try JSONDecoder().decode(BackupBundle.self, from: data)

        #expect(decoded.games.count == 2)
        #expect(Set(decoded.games.map(\.modeRaw)) == Set([GameMode.lms.rawValue, GameMode.predictor.rawValue]))
    }
}
