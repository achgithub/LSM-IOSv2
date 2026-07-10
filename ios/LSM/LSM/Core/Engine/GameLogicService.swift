import Foundation
import SwiftData
import os

private let gameLifecycleLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "lsm", category: "game-lifecycle")

/// Outcome of closing a round, for the UI to react to.
struct RoundCloseResult {
    let eliminated: [Player]
    let survivors: [Player]
    let allEliminated: Bool
    let remainingActive: Int
}

/// Adapter between SwiftData @Model objects and the pure `GameEngine`.
/// Keeps the engine free of persistence concerns.
enum GameLogicService {

    // MARK: - Lifecycle

    /// Deletes a game locally and, if it was ever pushed to the cloud, fires a
    /// best-effort cleanup call so its round/enrollment/submission rows in the
    /// worker-api don't linger indefinitely after the on-device copy is gone.
    /// Player tokens are untouched — they're one global link per player,
    /// shared across all of that player's games.
    static func deleteGame(_ game: Game, context: ModelContext) {
        let cloudToken = game.cloudGameToken
        context.delete(game)
        guard let cloudToken else { return }
        Task {
            do {
                try await SubmissionsClient.shared.deleteGame(gameToken: cloudToken)
            } catch {
                gameLifecycleLog.warning("Cloud cleanup failed for deleted game \(cloudToken): \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Used teams & eligibility

    /// Teams a player has used in previous *closed* rounds, counting only rounds
    /// after their team-pool reset boundary (a tie resolution can reopen the pool).
    static func usedTeamIds(for player: Player) -> Set<Int> {
        var used: Set<Int> = []
        for pick in player.picks where pick.round?.status == .closed {
            if let number = pick.round?.roundNumber, number <= player.teamPoolResetAfterRound { continue }
            used.insert(pick.teamId)
        }
        return used
    }

    /// Teams playing in a round, as engine `TeamRef`s (with positions). Each
    /// `TeamRef` is scoped to the specific fixture it came from — a team
    /// playing twice in the round (rearranged fixtures) appears twice, once
    /// per fixture, so a pick can record which occurrence it's backing.
    static func teamRefs(
        forFixtureIds ids: [Int],
        fixtures: [MatchDTO],
        teamsById: [Int: TeamDTO],
        standingsByTeam: [Int: StandingDTO]
    ) -> [TeamRef] {
        let idSet = Set(ids)
        var refs: [TeamRef] = []
        for fixture in fixtures where idSet.contains(fixture.id) {
            let home = teamsById[fixture.homeTeamId]
            let away = teamsById[fixture.awayTeamId]
            let homeName = home?.shortName ?? home?.name ?? "Team \(fixture.homeTeamId)"
            let awayName = away?.shortName ?? away?.name ?? "Team \(fixture.awayTeamId)"
            refs.append(TeamRef(
                id: fixture.homeTeamId, name: homeName,
                position: standingsByTeam[fixture.homeTeamId]?.position,
                fixtureId: fixture.id, opponentName: awayName
            ))
            refs.append(TeamRef(
                id: fixture.awayTeamId, name: awayName,
                position: standingsByTeam[fixture.awayTeamId]?.position,
                fixtureId: fixture.id, opponentName: homeName
            ))
        }
        return refs
    }

    static func pick(for player: Player, in round: Round) -> Pick? {
        round.picks.first { $0.player?.id == player.id }
    }

    // MARK: - Rounds & picks

    static func nextRoundNumber(for game: Game) -> Int {
        (game.rounds.map(\.roundNumber).max() ?? 0) + 1
    }

    /// Opens a round, admitting only fixtures within the shared
    /// `FixtureHorizon` (see fixture-horizon-logic design). `fixtures` is the
    /// caller's loaded fixture pool, used to look up each requested id's
    /// league/kickoff for that check — pass `[]` (the default) for synthetic
    /// callers like the tutorial, whose scripted fixture ids won't be found
    /// in the pool and so pass through untouched, same as a manual fixture.
    /// This is the actual enforcement point (not the round-open UI), since
    /// every mode's round creation funnels through here.
    @discardableResult
    static func openRound(
        in game: Game,
        fixtureIds: [Int],
        fixtures: [MatchDTO] = [],
        deadline: Date,
        roundType: RoundType = .normal,
        context: ModelContext
    ) -> Round {
        let manualLeagueId = ManualFixtureService.leagueId(for: game)
        let realFixtures = fixtures.filter { $0.leagueId != manualLeagueId }
        let eligible = FixtureHorizon.eligibleFixtureIds(fixtures: realFixtures)
        let knownRealIds = Set(realFixtures.map(\.id))
        let admittedIds = fixtureIds.filter { !knownRealIds.contains($0) || eligible.contains($0) }

        let round = Round(
            roundNumber: nextRoundNumber(for: game),
            deadline: deadline,
            fixtureIds: admittedIds,
            roundType: roundType,
            game: game
        )
        context.insert(round)
        if game.status == .setup { game.status = .active }
        return round
    }

    /// Set or change a player's pick for a round (clears any prior result).
    /// Always deletes-and-recreates rather than mutating an existing pick's
    /// `teamId` in place: mutating an attribute on an already-related SwiftData
    /// object doesn't reliably propagate to the row in one pass (the row shows
    /// the old team until the screen is re-entered), whereas inserting a fresh
    /// `Pick` and wiring its relationships does update synchronously — so
    /// changing a pick (e.g. overriding an auto-assign) reuses that same path.
    static func setPick(player: Player, round: Round, teamId: Int, fixtureId: Int? = nil, context: ModelContext) {
        if let existing = pick(for: player, in: round) {
            context.delete(existing)
        }
        let newPick = Pick(teamId: teamId, fixtureId: fixtureId)
        context.insert(newPick)
        newPick.player = player
        newPick.round = round
    }

    /// Remove a player's pick for a round (e.g. picked in error before close).
    static func clearPick(player: Player, round: Round, context: ModelContext) {
        guard let existing = pick(for: player, in: round) else { return }
        context.delete(existing)
    }

    /// Engine-driven auto-assign for active players who have no pick yet.
    /// Returns the proposed assignments (player → team, with the specific
    /// fixture it was assigned from) without committing, so the UI can preview
    /// before confirming.
    static func proposeAutoAssign(
        round: Round,
        game: Game,
        teamRefs: [TeamRef]
    ) -> [(player: Player, team: TeamRef)] {
        let unpicked = game.activePlayers.filter { pick(for: $0, in: round) == nil }
        let states = unpicked.map {
            PlayerAssignmentState(id: $0.id, usedTeamIds: usedTeamIds(for: $0))
        }
        let input = AutoAssignInput(fixtureTeams: teamRefs, players: states, allowRepeats: game.allowRepeats)
        let assignments = GameEngine.autoAssign(input)
        return unpicked.compactMap { player in
            assignments[player.id].map { (player, $0) }
        }
    }

    // MARK: - Results

    /// Apply a fixture result to every pick on either of its two teams (§6.5).
    /// A pick with a `fixtureId` only reacts to that exact fixture — needed
    /// because a team can play twice in a round (rearranged fixtures), so a
    /// win in one and a loss in the other must not overwrite each other.
    /// Picks made before `fixtureId` existed (nil) fall back to matching by
    /// team alone, same as before.
    static func applyResult(
        fixtureId: Int,
        homeTeamId: Int,
        awayTeamId: Int,
        outcome: FixtureOutcome,
        round: Round
    ) {
        for pick in round.picks {
            guard pick.fixtureId == nil || pick.fixtureId == fixtureId else { continue }
            if pick.teamId == homeTeamId {
                pick.result = homeResult(outcome)
            } else if pick.teamId == awayTeamId {
                pick.result = awayResult(outcome)
            }
        }
    }

    private static func homeResult(_ outcome: FixtureOutcome) -> PickResult {
        switch outcome {
        case .homeWin: return .win
        case .awayWin: return .loss
        case .draw: return .draw
        case .postponed: return .postponed
        }
    }

    private static func awayResult(_ outcome: FixtureOutcome) -> PickResult {
        switch outcome {
        case .homeWin: return .loss
        case .awayWin: return .win
        case .draw: return .draw
        case .postponed: return .postponed
        }
    }

    /// Map a provider winner string to a FixtureOutcome (for "pull from server").
    static func outcome(fromWinner winner: String?) -> FixtureOutcome? {
        switch winner {
        case "HOME_TEAM": return .homeWin
        case "AWAY_TEAM": return .awayWin
        case "DRAW": return .draw
        default: return nil
        }
    }

    // MARK: - Close round

    /// Compute eliminations, update player statuses/stats, mark the round closed.
    static func closeRound(
        _ round: Round,
        game: Game,
        context: ModelContext
    ) -> RoundCloseResult {
        let activeBefore = game.players.filter { $0.status == .active }

        let outcomes: [PickOutcome] = activeBefore.compactMap { player in
            guard let pick = pick(for: player, in: round) else { return nil }
            return PickOutcome(playerId: player.id, result: pick.result)
        }
        let elimination = GameEngine.computeEliminations(
            picks: outcomes,
            drawEliminates: game.drawEliminates,
            postponedEliminates: game.postponedEliminates
        )
        let eliminatedIds = Set(elimination.eliminatedPlayerIds)

        var eliminated: [Player] = []
        var survivors: [Player] = []
        for player in activeBefore {
            if eliminatedIds.contains(player.id) {
                player.status = .eliminated
                eliminated.append(player)
            } else {
                survivors.append(player)
            }
        }

        round.status = .closed
        let allEliminated = GameEngine.isAllEliminated(
            activeBefore: activeBefore.count,
            eliminatedThisRound: eliminated.count
        )
        return RoundCloseResult(
            eliminated: eliminated,
            survivors: survivors,
            allEliminated: allEliminated,
            remainingActive: survivors.count
        )
    }

    // MARK: - Apply a resolution outcome

    /// Apply a `TieOutcome` (manager's in-the-moment choice) to the game, and
    /// record it so its outcome card stays shareable. Returns the follow-up round
    /// type to open next, or nil when the game is now complete.
    @discardableResult
    static func apply(_ outcome: TieOutcome, game: Game) -> RoundType? {
        let playersById = Dictionary(game.players.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let currentRoundNumber = game.currentRound?.roundNumber ?? 0

        switch outcome {
        case .winners(let ids):
            let winners = Set(ids)
            for player in game.players {
                player.status = winners.contains(player.id) ? .winner : .eliminated
            }
            game.status = .complete
            game.lastOutcome = winners.count > 1 ? .split : .winner
            return nil

        case .rollWeek(let tiedIds, let resetPool):
            for id in tiedIds {
                guard let player = playersById[id] else { continue }
                player.status = .active
                // Pool exhausted for the whole group → reopen it so they can pick.
                if resetPool { player.teamPoolResetAfterRound = currentRoundNumber }
            }
            game.lastOutcome = .rollWeek
            return .rollover

        case .everyoneBackIn(let ids):
            for id in ids {
                guard let player = playersById[id] else { continue }
                player.status = .active
                player.teamPoolResetAfterRound = currentRoundNumber
            }
            game.lastOutcome = .everyoneBackIn
            return .rollover
        }
    }
}
