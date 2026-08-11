import Testing
import Foundation
import SwiftData
@testable import LSM

/// Regression cover for `requiredMPGCount` — how many opponents each player
/// must target in a Killer round. Locks in the fixed table (always leave
/// exactly one opponent safe, except the final head-to-head where the pool
/// is a single opponent) after a bug where the old formula
/// (`activePlayers - 1`) targeted every possible opponent, leaving no one
/// safe at any player count.
struct KillerScoringServiceTests {

    @Test func leavesExactlyOneOpponentSafeAboveTheFinal() {
        #expect(KillerScoringService.requiredMPGCount(activePlayers: 6, maxMPG: 5) == 4)
        #expect(KillerScoringService.requiredMPGCount(activePlayers: 5, maxMPG: 5) == 3)
        #expect(KillerScoringService.requiredMPGCount(activePlayers: 4, maxMPG: 5) == 2)
        #expect(KillerScoringService.requiredMPGCount(activePlayers: 3, maxMPG: 5) == 1)
    }

    @Test func finalHeadToHeadHasNoOneToSpare() {
        // Only one opponent exists at all, so it can't be left safe.
        #expect(KillerScoringService.requiredMPGCount(activePlayers: 2, maxMPG: 5) == 1)
    }

    @Test func maxMPGStillCapsLargeLobbies() {
        // 10 active players, pool of 9 — capped at maxMPG, not activePlayers - 2.
        #expect(KillerScoringService.requiredMPGCount(activePlayers: 10, maxMPG: 5) == 5)
    }

    @Test func gameAlreadyDecidedNeedsNoTargets() {
        #expect(KillerScoringService.requiredMPGCount(activePlayers: 1, maxMPG: 5) == 0)
        #expect(KillerScoringService.requiredMPGCount(activePlayers: 0, maxMPG: 5) == 0)
    }

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Game.self, Player.self, Round.self, KillerPrediction.self, KillerPlayerState.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    /// Regression for the double-close race: `closeRound` re-entering after
    /// `round.status` already flipped to `.closed` (e.g. a second tap racing
    /// the async PWA pending-submissions check in the view) must be a no-op,
    /// not re-apply Kill Phase Hit damage and Accuracy Table credit a second
    /// time.
    @Test func closingAnAlreadyClosedRoundIsANoOp() throws {
        let context = try makeContext()
        let g = Game(name: "Test", season: "2025/26", allowRepeats: true, mode: .killer, killerBuildPhaseRounds: 0)
        context.insert(g)
        let alice = Player(name: "Alice", game: g)
        let bob = Player(name: "Bob", game: g)
        context.insert(alice)
        context.insert(bob)
        let aliceState = KillerPlayerState(player: alice, game: g)
        let bobState = KillerPlayerState(player: bob, game: g)
        context.insert(aliceState)
        context.insert(bobState)
        alice.killerState = aliceState
        bob.killerState = bobState
        g.players = [alice, bob]

        // Round 1, Kill Phase (killerBuildPhaseRounds: 0). Alice correctly
        // predicts fixture 101 and lands her Hit on Bob.
        let round = Round(roundNumber: 1, deadline: .now, fixtureIds: [101], game: g)
        context.insert(round)
        let prediction = KillerPrediction(
            fixtureId: 101, predictedOutcome: .homeWin, hitTargetPlayerId: bob.id, player: alice, round: round
        )
        context.insert(prediction)
        round.killerPredictions = [prediction]

        _ = try KillerScoringService.closeRound(round, game: g, finalOutcomes: [101: .homeWin], context: context)

        #expect(round.status == .closed)
        #expect(bobState.lives == 0) // hit landed, one life lost
        #expect(aliceState.correctPredictions == 1)
        #expect(aliceState.successfulHitsLanded == 1)

        // Re-entrant close (the race): must not double-apply anything.
        _ = try KillerScoringService.closeRound(round, game: g, finalOutcomes: [101: .homeWin], context: context)

        #expect(bobState.lives == 0)
        #expect(aliceState.correctPredictions == 1)
        #expect(aliceState.successfulHitsLanded == 1)
    }
}
