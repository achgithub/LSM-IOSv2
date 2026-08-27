import Foundation

/// Where a game's current round actually stands, read straight off the clock
/// and cached fixture data rather than `Round.status`: the engine never
/// actually sets `.picks`/`.results` (rounds only ever go open → closed —
/// see `GameLogicService`/`PredictorScoringService`/`KillerScoringService`),
/// so a status enum that never moves can't tell "deadline passed" from
/// "kickoff happened" from "all results in." Both `NextUpStep` (the Next Up
/// action) and `ManagerRoundStatus` (the badge) derive their text from this
/// one phase so they can't drift apart or go stale at different times.
enum RoundPhase {
    /// The game's finished (winner declared/complete) — distinct from
    /// `.closed` (a mid-competition round closed, next one still to open),
    /// since only `.closed` should nudge the manager to open another round.
    case complete
    /// Never had a round (or a closed one) and doesn't have enough eligible
    /// players yet to open one — mirrors `GameWizardViewV2`'s own
    /// `addPlayers` gate (`activePlayers`/`players.count < 2`) rather than
    /// inventing a second threshold; a fresh game with 0-1 players (all
    /// `NewGameViewV2` creation paths seed at most the manager) needs
    /// players before "Open Round" would even be tappable there.
    case addPlayers
    /// No current round, and enough players to open one — a brand-new game
    /// past `.addPlayers`, or the very first round for a game some other
    /// path already gave a full roster to.
    case openRound
    /// Round's been closed out (results processed) — next step is opening
    /// the following round, same destination as `.openRound` above but a
    /// distinct case so `ManagerRoundStatus` can still say "Round N closed"
    /// rather than "Not started."
    case closed
    /// Before the deadline — submission window's still open.
    case beforeDeadline
    /// Deadline's passed but kickoff hasn't (per cached fixture data) — last
    /// call to catch anyone who didn't submit before the window's moot.
    case beforeKickoff
    /// Kickoff's happened; not every fixture's finished or postponed yet.
    case live(finished: Int, total: Int)
    /// Every fixture's finished/postponed — ready to score the round.
    case readyToProcess

    /// `data` is whatever's already cached for the game's leagues (never
    /// fetched live here — matches `LeagueData`'s own cache-only policy for
    /// round-flow screens); with nothing cached yet, fixture status just
    /// reads as "not started," which only affects the beforeKickoff/live
    /// split, not whether there's a round to act on at all.
    static func make(for game: Game, data: LeagueData?) -> RoundPhase {
        guard game.status != .complete else { return .complete }
        guard let round = game.currentRound else {
            let eligible: Int
            switch game.mode {
            case .lms, .killer: eligible = game.activePlayers.count
            case .predictor: eligible = game.players.count
            }
            return eligible < 2 ? .addPlayers : .openRound
        }
        guard round.status != .closed else { return .closed }
        guard Date() >= round.deadline else { return .beforeDeadline }

        let total = round.fixtureIds.count
        guard total > 0 else { return .beforeKickoff }
        let fixtures = (data?.matches ?? []).filter { round.fixtureIds.contains($0.id) }

        let hasKickedOff = fixtures.contains { fixture in
            guard let kickoff = FixtureFormat.kickoffDate(fixture.kickoff) else { return false }
            return kickoff <= Date()
        }
        guard hasKickedOff else { return .beforeKickoff }

        let finished = fixtures.filter { $0.isFinished || $0.isPostponedOrCancelled }.count
        guard fixtures.count >= total, finished >= total else {
            return .live(finished: finished, total: total)
        }
        return .readyToProcess
    }
}

/// The single next action a manager should take on a game — what
/// `GameSummaryRow`'s Next Up line/button on the Games portal surfaces.
/// A nudge read off `RoundPhase`, never a gate: the manager can always enter
/// or correct a pick regardless of which case this returns (see
/// `GameSummaryRow.nextUpButton`, which opens the same picks sheet for both
/// `.enterPicks` and `.confirmEntries`).
enum NextUpStep {
    /// Not enough eligible players yet to open a round — see
    /// `RoundPhase.addPlayers`.
    case addPlayers
    /// Ready to open a round — a brand-new game with enough players, or the
    /// game's previous round just closed. See `RoundPhase.openRound`/
    /// `.closed`.
    case openRound
    /// Before the deadline — manual manager entry, or (PWA games) reviewing
    /// what's come in via the submission queue so far. Same destination
    /// either way, just a different verb depending which one applies.
    case enterPicks(pwaEnabled: Bool)
    /// Deadline's passed but kickoff hasn't (per cached fixture data) — last
    /// call to catch anyone who didn't submit before the window's moot.
    case confirmEntries(pwaEnabled: Bool)
    /// Kickoff's happened; not every fixture's finished or postponed yet.
    case matchesInProgress(finished: Int, total: Int)
    /// Every fixture's finished/postponed — ready to score the round.
    case processResults
    /// No open round to act on (the game's complete).
    case none

    static func make(for game: Game, data: LeagueData?, pwaEnabled: Bool) -> NextUpStep {
        switch RoundPhase.make(for: game, data: data) {
        case .complete:
            return .none
        case .addPlayers:
            return .addPlayers
        case .openRound, .closed:
            return .openRound
        case .beforeDeadline:
            return .enterPicks(pwaEnabled: pwaEnabled)
        case .beforeKickoff:
            return .confirmEntries(pwaEnabled: pwaEnabled)
        case .live(let finished, let total):
            return .matchesInProgress(finished: finished, total: total)
        case .readyToProcess:
            return .processResults
        }
    }
}
