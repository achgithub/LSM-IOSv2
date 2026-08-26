import Foundation

/// The single next action a manager should take on a game — what
/// `GameSummaryRow`'s Next Up line/button on the Games portal surfaces.
///
/// Deliberately not driven by `Round.status` beyond open/closed: the engine
/// never actually sets `.picks`/`.results` (rounds only ever go
/// open → closed — see `GameLogicService`/`PredictorScoringService`/
/// `KillerScoringService`), so "has the deadline passed" and "have this
/// round's fixtures kicked off/finished" are read straight from the clock
/// and from cached `MatchDTO`s instead of a status enum that never moves.
enum NextUpStep {
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
    /// No open round to act on (setup, or the game's complete).
    case none

    /// `data` is whatever's already cached for the game's leagues (never
    /// fetched live here — matches `LeagueData`'s own cache-only policy for
    /// round-flow screens); with nothing cached yet, fixture status just
    /// reads as "not started," which only affects the confirm/in-progress
    /// split, not whether there's a next step at all.
    static func make(for game: Game, data: LeagueData?, pwaEnabled: Bool) -> NextUpStep {
        guard let round = game.currentRound, round.status != .closed else { return .none }
        guard Date() >= round.deadline else { return .enterPicks(pwaEnabled: pwaEnabled) }

        let total = round.fixtureIds.count
        guard total > 0 else { return .confirmEntries(pwaEnabled: pwaEnabled) }
        let fixtures = (data?.matches ?? []).filter { round.fixtureIds.contains($0.id) }

        let hasKickedOff = fixtures.contains { fixture in
            guard let kickoff = FixtureFormat.kickoffDate(fixture.kickoff) else { return false }
            return kickoff <= Date()
        }
        guard hasKickedOff else { return .confirmEntries(pwaEnabled: pwaEnabled) }

        let finished = fixtures.filter { $0.isFinished || $0.isPostponedOrCancelled }.count
        guard fixtures.count >= total, finished >= total else {
            return .matchesInProgress(finished: finished, total: total)
        }
        return .processResults
    }
}
