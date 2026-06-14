import Foundation

/// Pure value types for the game-logic engine. The engine has no SwiftData or
/// SwiftUI dependency — it operates on these plain inputs so it is fast and
/// deterministic to unit-test. A thin adapter maps the @Model objects to these.

/// A team in a round's fixtures, with its league position if standings are known.
nonisolated struct TeamRef: Equatable, Sendable {
    let id: Int
    let name: String
    let position: Int?   // nil when standings are unavailable
}

/// An active player's state needed for auto-assign: which team ids they've used
/// in previous closed rounds.
nonisolated struct PlayerAssignmentState: Equatable, Sendable {
    let id: UUID
    let usedTeamIds: Set<Int>
}

nonisolated struct AutoAssignInput: Sendable {
    let fixtureTeams: [TeamRef]
    let players: [PlayerAssignmentState]
    let allowRepeats: Bool
}

/// One player's pick result for elimination computation.
nonisolated struct PickOutcome: Equatable, Sendable {
    let playerId: UUID
    let result: PickResult?   // nil = unresolved (round shouldn't close yet)
}

nonisolated struct EliminationResult: Equatable, Sendable {
    let eliminatedPlayerIds: [UUID]
    let survivingPlayerIds: [UUID]
}

/// A tied player at the all-eliminated moment, with the stats needed by the
/// longevity rule and the team they picked in the tie round (for rollover).
nonisolated struct TiePlayer: Equatable, Sendable {
    let id: UUID
    let roundsSurvived: Int
    let weakPicks: Int
    let thisRoundTeamId: Int?
}

/// How a round-close resolves: either the chosen tie rule (spec §13c.2) or a
/// manager manual override. The adapter applies the outcome to the game.
nonisolated enum TieOutcome: Equatable, Sendable {
    case jointWinners([UUID])                                   // Split
    case rollover(reinstated: [UUID], usedTeamToAdd: [UUID: Int]) // Rollover round
    case fullReset(reinstatedAll: [UUID])                       // Full reset
    case suddenDeathPlayoff([UUID])                             // Sudden death
    case singleWinner(UUID, reason: String)                    // Longevity

    /// Manager override — declare winner(s) and complete the game, regardless of
    /// the configured tie rule. Available at any round close.
    case manualWinners([UUID])
}
