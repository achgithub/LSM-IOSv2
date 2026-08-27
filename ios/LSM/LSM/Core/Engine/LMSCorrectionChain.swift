import Foundation
import SwiftData

/// LMS's round-correction resolution — see `RoundCorrectionWizardView`'s doc
/// comment for the mode split. A lazy, one-conflict-at-a-time loop, not a
/// whole-game replay: fixing a target round's pick can require freeing a
/// team a later closed round is already holding, which itself needs fixing
/// first (recursively, if that round's own new team is also spoken for
/// further out), before the target round's correction is actually valid.
/// Only the rounds pulled into the resulting chain are touched — everything
/// else keeps its existing, still-valid outcome. `usedTeamIds`/`blockingRound`
/// both take a `resolved: [Int: Int]` map (round number → its new team, for
/// rounds already finalized earlier in this same chain) so a team just
/// reassigned to round 3 correctly counts as "used" there — not its old,
/// now-superseded pick — when checking round 2 (or a hypothetical round 4)
/// against it.
enum LMSCorrectionChain {
    /// One round's resolved correction, in the order they'll be applied.
    struct Step {
        let round: Round
        let oldTeamId: Int?
        let newTeamId: Int
        let newFixtureId: Int?
        /// Derived from the corrected team's actual fixture result — nil if
        /// the result can't be determined (fixture data not cached, or the
        /// match has no winner recorded yet).
        let newResult: PickResult?
        /// Whether the player is active after this round, per the corrected
        /// result and the game's draw/postponed rules. Only meaningful when
        /// `newResult != nil`.
        let survivesRound: Bool
    }

    /// This player's used-team pool as of right now, substituting `resolved`
    /// rounds' new team for their stored (soon-to-be-superseded) one.
    static func usedTeamIds(for player: Player, resolved: [Int: Int]) -> Set<Int> {
        var used: Set<Int> = []
        for pick in player.picks {
            guard let round = pick.round, round.status == .closed else { continue }
            if round.roundNumber <= player.teamPoolResetAfterRound { continue }
            used.insert(resolved[round.roundNumber] ?? pick.teamId)
        }
        return used
    }

    /// The nearest closed round after `targetRoundNumber` currently holding
    /// `teamId` (stored pick, or its `resolved` replacement if it's already
    /// been corrected earlier in this chain) — nil if nothing's blocking.
    static func blockingRound(for player: Player, teamId: Int, targetRoundNumber: Int, resolved: [Int: Int]) -> Round? {
        var candidates: [Round] = []
        for pick in player.picks {
            guard let round = pick.round, round.status == .closed, round.roundNumber > targetRoundNumber else { continue }
            let effectiveTeamId = resolved[round.roundNumber] ?? pick.teamId
            if effectiveTeamId == teamId { candidates.append(round) }
        }
        return candidates.min { $0.roundNumber < $1.roundNumber }
    }

    /// Teams this round could reassign to, given what's already been
    /// resolved elsewhere in this chain.
    static func eligibleTeams(for player: Player, round: Round, game: Game, data: LeagueData?, resolved: [Int: Int]) -> [TeamRef] {
        guard let data else { return [] }
        let refs = GameLogicService.teamRefs(
            forFixtureIds: round.fixtureIds, fixtures: data.matches,
            teamsById: data.teamsById, standingsByTeam: data.standingsByTeam
        )
        let used = usedTeamIds(for: player, resolved: resolved)
        let standingsKnown = refs.contains { $0.position != nil }
        return GameEngine.orderedAvailableTeams(fixtureTeams: refs, used: used, allowRepeats: game.allowRepeats, standingsKnown: standingsKnown)
    }

    /// Result + survives for a team newly assigned to a round, derived from
    /// the fixture's already-known/stored outcome — the same source
    /// `ResultsEntryViewV2` uses, not a manual manager judgment call.
    static func resolve(teamId: Int, fixtureId: Int?, round: Round, game: Game, data: LeagueData?) -> (result: PickResult?, survives: Bool) {
        guard let data else { return (nil, true) }
        let fixture = data.matches.first { candidate in
            round.fixtureIds.contains(candidate.id)
                && (candidate.homeTeamId == teamId || candidate.awayTeamId == teamId)
                && (fixtureId == nil || candidate.id == fixtureId)
        }
        guard let fixture, let outcome = GameLogicService.outcome(fromWinner: fixture.winner) else {
            return (nil, true)
        }
        let result = GameLogicService.result(forTeamId: teamId, homeTeamId: fixture.homeTeamId, awayTeamId: fixture.awayTeamId, outcome: outcome)
        let eliminates: Bool
        switch result {
        case .loss: eliminates = true
        case .win, .none: eliminates = false
        case .draw: eliminates = game.drawEliminates
        case .postponed: eliminates = game.postponedEliminates
        }
        return (result, !eliminates)
    }

    /// Commit every step, ascending round order — delete-and-recreate each
    /// round's `Pick` (`GameLogicService.setPick`'s documented convention;
    /// mutating `Pick.teamId` in place doesn't reliably propagate), set its
    /// result, and finally set `Player.status` from the last (most recent)
    /// step's outcome — the rounds after the chain, if any, are untouched
    /// and their own already-computed outcomes still stand.
    static func apply(_ steps: [Step], player: Player, context: ModelContext) {
        let ordered = steps.sorted { $0.round.roundNumber < $1.round.roundNumber }
        for step in ordered {
            GameLogicService.setPick(player: player, round: step.round, teamId: step.newTeamId, fixtureId: step.newFixtureId, context: context)
            GameLogicService.pick(for: player, in: step.round)?.result = step.newResult
        }
        if let last = ordered.last {
            player.status = last.survivesRound ? .active : .eliminated
        }
    }
}
