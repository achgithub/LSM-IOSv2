import Testing
import Foundation
@testable import LSM

struct AutoAssignTests {
    let top = TeamRef(id: 1, name: "Alpha", position: 1)
    let mid = TeamRef(id: 2, name: "Bravo", position: 10)
    let bottom = TeamRef(id: 3, name: "Charlie", position: 20)
    var fixtures: [TeamRef] { [top, mid, bottom] }

    @Test func assignsBottomOfTableFirstWhenStandingsKnown() {
        let p = PlayerAssignmentState(id: UUID(), usedTeamIds: [])
        let result = GameEngine.autoAssign(
            AutoAssignInput(fixtureTeams: fixtures, players: [p], allowRepeats: false)
        )
        #expect(result[p.id] == bottom.id)
    }

    @Test func excludesUsedTeamsWhenRepeatsOff() {
        let ordered = GameEngine.orderedAvailableTeams(
            fixtureTeams: fixtures, used: [bottom.id], allowRepeats: false, standingsKnown: true
        )
        #expect(ordered.map(\.id) == [mid.id, top.id])
        #expect(!ordered.contains { $0.id == bottom.id })
    }

    @Test func includesUsedAtBottomWhenRepeatsOn() {
        let ordered = GameEngine.orderedAvailableTeams(
            fixtureTeams: fixtures, used: [bottom.id], allowRepeats: true, standingsKnown: true
        )
        #expect(ordered.map(\.id) == [mid.id, top.id, bottom.id])
    }

    @Test func autoAssignSkipsUsedTeamsAndTakesNextLowest() {
        // Player already used the bottom team → auto-assign must traverse UP the
        // table to the next-lowest team they haven't used (not re-assign bottom).
        let p = PlayerAssignmentState(id: UUID(), usedTeamIds: [bottom.id])
        let result = GameEngine.autoAssign(
            AutoAssignInput(fixtureTeams: fixtures, players: [p], allowRepeats: false)
        )
        #expect(result[p.id] == mid.id)
    }

    @Test func noAssignmentWhenAllUsedAndRepeatsOff() {
        let p = PlayerAssignmentState(id: UUID(), usedTeamIds: [top.id, mid.id, bottom.id])
        let result = GameEngine.autoAssign(
            AutoAssignInput(fixtureTeams: fixtures, players: [p], allowRepeats: false)
        )
        #expect(result[p.id] == nil)
    }

    @Test func assignsUsedWhenAllUsedAndRepeatsOn() {
        let p = PlayerAssignmentState(id: UUID(), usedTeamIds: [top.id, mid.id, bottom.id])
        let result = GameEngine.autoAssign(
            AutoAssignInput(fixtureTeams: fixtures, players: [p], allowRepeats: true)
        )
        #expect(result[p.id] == bottom.id)
    }

    @Test func fallsBackToAlphabeticalWhenStandingsUnknown() {
        let zulu = TeamRef(id: 1, name: "Zulu", position: nil)
        let alpha = TeamRef(id: 2, name: "Alpha", position: nil)
        let ordered = GameEngine.orderedAvailableTeams(
            fixtureTeams: [zulu, alpha], used: [], allowRepeats: false, standingsKnown: false
        )
        #expect(ordered.map(\.name) == ["Alpha", "Zulu"])
    }

    @Test func playersAssignedIndependentlyCanShareTeam() {
        let p1 = PlayerAssignmentState(id: UUID(), usedTeamIds: [])
        let p2 = PlayerAssignmentState(id: UUID(), usedTeamIds: [])
        let result = GameEngine.autoAssign(
            AutoAssignInput(fixtureTeams: fixtures, players: [p1, p2], allowRepeats: false)
        )
        #expect(result[p1.id] == bottom.id)
        #expect(result[p2.id] == bottom.id)
    }
}
