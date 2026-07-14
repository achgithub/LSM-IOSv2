import Testing
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
}
