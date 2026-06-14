import Testing
import Foundation
@testable import LMS

struct TieResolutionTests {

    private func player(rounds: Int, weak: Int, team: Int? = nil) -> TiePlayer {
        TiePlayer(id: UUID(), roundsSurvived: rounds, weakPicks: weak, thisRoundTeamId: team)
    }

    @Test func splitMakesAllTiedJointWinners() {
        let p1 = player(rounds: 5, weak: 0)
        let p2 = player(rounds: 5, weak: 0)
        let out = GameEngine.resolveTie(rule: .split, tiedPlayers: [p1, p2], allPlayerIds: [p1.id, p2.id])
        #expect(out == .jointWinners([p1.id, p2.id]))
    }

    @Test func rolloverReinstatesAndRecordsLosingTeams() {
        let p1 = player(rounds: 5, weak: 0, team: 10)
        let p2 = player(rounds: 5, weak: 0, team: 11)
        let out = GameEngine.resolveTie(rule: .rolloverRound, tiedPlayers: [p1, p2], allPlayerIds: [p1.id, p2.id])
        #expect(out == .rollover(reinstated: [p1.id, p2.id], usedTeamToAdd: [p1.id: 10, p2.id: 11]))
    }

    @Test func fullResetReinstatesEveryoneIncludingPreviouslyEliminated() {
        let p1 = player(rounds: 5, weak: 0)
        let alreadyOut = UUID()
        let out = GameEngine.resolveTie(rule: .fullReset, tiedPlayers: [p1], allPlayerIds: [p1.id, alreadyOut])
        #expect(out == .fullReset(reinstatedAll: [p1.id, alreadyOut]))
    }

    @Test func suddenDeathStartsPlayoff() {
        let p1 = player(rounds: 5, weak: 0)
        let p2 = player(rounds: 5, weak: 0)
        let out = GameEngine.resolveTie(rule: .suddenDeath, tiedPlayers: [p1, p2], allPlayerIds: [p1.id, p2.id])
        #expect(out == .suddenDeathPlayoff([p1.id, p2.id]))
    }

    @Test func longevityWinsOnMostRoundsSurvived() {
        let winner = player(rounds: 14, weak: 3)
        let loser = player(rounds: 12, weak: 0)
        let out = GameEngine.resolveTie(rule: .longevity, tiedPlayers: [winner, loser], allPlayerIds: [winner.id, loser.id])
        #expect(out == .singleWinner(winner.id, reason: "longevity"))
    }

    @Test func longevityTiebreaksOnFewestWeakPicks() {
        let winner = player(rounds: 14, weak: 1)
        let loser = player(rounds: 14, weak: 4)
        let out = GameEngine.resolveTie(rule: .longevity, tiedPlayers: [winner, loser], allPlayerIds: [winner.id, loser.id])
        #expect(out == .singleWinner(winner.id, reason: "fewest weak picks"))
    }

    @Test func longevityFallsBackToSplitWhenFullyTied() {
        let p1 = player(rounds: 14, weak: 2)
        let p2 = player(rounds: 14, weak: 2)
        let out = GameEngine.resolveTie(rule: .longevity, tiedPlayers: [p1, p2], allPlayerIds: [p1.id, p2.id])
        #expect(out == .jointWinners([p1.id, p2.id]))
    }

    @Test func managerCanDeclareWinnersManually() {
        let a = UUID(), b = UUID()
        #expect(GameEngine.declareWinners([a, b]) == .manualWinners([a, b]))
        #expect(GameEngine.declareWinners([a]) == .manualWinners([a]))
    }
}
