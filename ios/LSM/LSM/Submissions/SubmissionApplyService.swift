import SwiftData
import OSLog

private let applyLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "lsm", category: "submissions")

/// Applies an approved submission's payload to the local Pick/Prediction data
/// for the given game/round. Shared by `SubmissionQueueView` (per-game) and
/// `SubmissionInboxViewV2` (cross-game) so the mode-dispatch logic exists
/// once.
enum SubmissionApplyService {
    /// The local manager's suffix — last 8 hex chars of the manager player's UUID.
    static func localManagerSuffix(for game: Game) -> String? {
        guard let manager = game.players.first(where: { $0.isManager }) else { return nil }
        return String(manager.id.uuidString.replacingOccurrences(of: "-", with: "").suffix(8)).lowercased()
    }

    @MainActor
    static func apply(_ result: ApproveResult, playerName: String, game: Game, round: Round, context: ModelContext) {
        // Validate that the submission came through an enrollment owned by this manager.
        if let resultSuffix = result.managerSuffix, let localSuffix = localManagerSuffix(for: game),
           resultSuffix != localSuffix {
            applyLog.warning("Approve skipped: managerSuffix mismatch (\(resultSuffix) ≠ \(localSuffix))")
            return
        }

        // Guard against a submission that was filled out against a round that's
        // since closed (e.g. approved late, after the manager already opened
        // the next round) — applying it to whatever round is passed in would be
        // silently wrong. A mismatch means the submission is stale.
        guard result.roundNumber == round.roundNumber else {
            applyLog.warning("Approve skipped: stale round (submission for \(result.roundNumber), open round is \(round.roundNumber))")
            return
        }

        // Find player by UUID first; fall back to name for pre-Phase-5 enrollments.
        let player = game.players.first(where: {
            $0.id.uuidString.lowercased() == result.localPlayerId.lowercased()
        }) ?? game.players.first(where: {
            $0.name.localizedCaseInsensitiveCompare(playerName) == .orderedSame
        })
        guard let player else { return }

        if game.mode == .lms, let teamId = result.payload.teamId {
            GameLogicService.setPick(
                player: player, round: round, teamId: teamId, fixtureId: result.payload.fixtureId, context: context
            )
        } else if game.mode == .predictor, let scores = result.payload.scores {
            for score in scores {
                PredictorScoringService.setPrediction(
                    player: player,
                    round: round,
                    fixtureId: score.fixtureId,
                    home: score.home,
                    away: score.away,
                    context: context
                )
            }
            // Apply joker if the player designated one.
            if let jokerScore = scores.first(where: { $0.isJoker == true }) {
                PredictorScoringService.setJoker(player: player, round: round, fixtureId: jokerScore.fixtureId)
            }
        } else if game.mode == .killer, let outcomes = result.payload.outcomes {
            for entry in outcomes {
                // A malformed/unknown outcome string skips just that fixture
                // rather than aborting the whole submission — matches the
                // "safely rejectable, not corrupting" requirement for
                // untrusted PWA payloads.
                guard let outcome = FixtureOutcome(rawValue: entry.outcome) else {
                    applyLog.warning("Skipped Killer outcome with unknown value: \(entry.outcome)")
                    continue
                }
                KillerScoringService.setPrediction(
                    player: player, round: round, fixtureId: entry.fixtureId, outcome: outcome, context: context
                )

                // Kill Phase only. A bad/unresolvable target UUID (malformed
                // string, or a player deactivated between push and
                // submission) just leaves the target unset for this fixture
                // rather than dropping the outcome too. `setHitTarget` itself
                // is the real enforcement gate for self-target/duplicate-
                // target — it already guards both and no-ops on violation
                // (see KillerScoringService), so this stays the backstop even
                // if the PWA's own client-side validation is bypassed.
                guard let hitTargetIdString = entry.hitTargetId,
                      let hitTargetId = UUID(uuidString: hitTargetIdString),
                      let target = game.players.first(where: { $0.id == hitTargetId }) else { continue }
                _ = KillerScoringService.setHitTarget(
                    player: player, round: round, fixtureId: entry.fixtureId, targetPlayerId: target.id, context: context
                )
            }
        }
        try? context.save()
    }
}
