import Foundation
import SwiftData

/// Which phase a Killer round falls in — rounds 1...killerBuildPhaseRounds are
/// Build (lives earned, no Hits); everything after is Kill (no more life
/// gains; predictions also fire a Hit at a chosen opponent).
enum KillerPhase {
    case build, kill
}

enum KillerScoringError: LocalizedError {
    case incompleteOutcomes

    var errorDescription: String? {
        "Every fixture must have a result entered before the round can be closed."
    }
}

/// Result of a round's elimination pass, for the UI to react to. Only
/// `.winner`/`.split` are game-deciding — `.notApplicable` covers both
/// "no one hit 0 this round" and "someone hit 0 but active players remain,"
/// neither of which ends the game.
enum KillerTieOutcome: Equatable {
    /// A single simultaneous zero-lives crossing decided by the Accuracy
    /// Table (then hit-count) tiebreak — this player wins the game outright.
    case winner(UUID)
    /// Still tied after both tiebreak criteria — the pot is auto-split among
    /// these player ids (all marked `.winner`). Returned only so the UI can
    /// message it (e.g. "Split between X and Y!"); not a pending decision.
    case split([UUID])
    case notApplicable
}

/// Killer scoring: lives, Build/Kill phases, and (from Milestone 3) Hit
/// resolution. Kept separate from `GameLogicService`/`PredictorScoringService`
/// — same rationale as Predictor's own service: Killer's phase-dependent
/// behavior and Hit side-effect don't belong threaded through either existing
/// engine. See the Killer implementation plan.
enum KillerScoringService {

    // MARK: - Phase / MPG count

    static func phase(for round: Round, game: Game) -> KillerPhase {
        round.roundNumber <= game.killerBuildPhaseRounds ? .build : .kill
    }

    /// Manager Picked Games count for a round, given the active player count.
    /// `N = min(maxMPG, activePlayers - 1)` — the only formula that guarantees
    /// the Kill Phase's "each Hit targets a different opponent" constraint is
    /// always satisfiable (N Hits need N distinct opponents).
    static func requiredMPGCount(activePlayers: Int, maxMPG: Int) -> Int {
        max(0, min(maxMPG, activePlayers - 1))
    }

    // MARK: - Player state

    /// Creates and attaches a `KillerPlayerState` for a player just added to a
    /// Killer game, if it doesn't already have one. No-op for non-Killer
    /// games. Called from every player-add site (New Game, Add Players) so no
    /// site can forget it.
    static func attachStateIfNeeded(to player: Player, game: Game, context: ModelContext) {
        guard game.mode == .killer, player.killerState == nil else { return }
        let state = KillerPlayerState(player: player, game: game)
        context.insert(state)
        player.killerState = state
    }

    // MARK: - Predictions

    static func predictions(for player: Player, in round: Round) -> [KillerPrediction] {
        round.killerPredictions.filter { $0.player?.id == player.id }
    }

    static func prediction(for player: Player, fixtureId: Int, in round: Round) -> KillerPrediction? {
        round.killerPredictions.first { $0.player?.id == player.id && $0.fixtureId == fixtureId }
    }

    /// Whether one player has fully completed their slate for a round: an
    /// outcome guess for every MPG fixture, plus — Kill Phase only — a hit
    /// target on each. Kill Phase's per-prediction hit target isn't optional
    /// once an outcome guess exists — unlike LMS/Predictor's simpler
    /// completeness check, this must also verify targets, or a player can
    /// show "complete" while still missing a required attack.
    static func slateComplete(for player: Player, round: Round, game: Game) -> Bool {
        let fixtureIds = Set(round.fixtureIds)
        guard !fixtureIds.isEmpty else { return false }
        let playerPredictions = predictions(for: player, in: round)
        let predictedIds = Set(playerPredictions.map(\.fixtureId))
        guard fixtureIds.isSubset(of: predictedIds) else { return false }
        guard phase(for: round, game: game) == .kill else { return true }
        return playerPredictions.allSatisfy { $0.hitTargetPlayerId != nil }
    }

    /// Whether every active player has fully completed their slate for the
    /// round — the gate `KillerResultsEntryView`'s "Close Round" checks
    /// before scoring, so a no-show player doesn't silently score nothing.
    static func allActivePlayersComplete(round: Round, game: Game) -> Bool {
        game.activePlayers.allSatisfy { slateComplete(for: $0, round: round, game: game) }
    }

    /// Set or change a player's Home/Draw/Away guess for one MPG fixture.
    /// Mirrors `PredictorScoringService.setPrediction`'s delete-and-recreate
    /// approach. Preserves any Hit-target already set on the existing row —
    /// Milestone 3's `setHitTarget` is the only thing that should clear it.
    static func setPrediction(
        player: Player,
        round: Round,
        fixtureId: Int,
        outcome: FixtureOutcome,
        context: ModelContext
    ) {
        let existingTarget = prediction(for: player, fixtureId: fixtureId, in: round)?.hitTargetPlayerId
        if let existing = prediction(for: player, fixtureId: fixtureId, in: round) {
            context.delete(existing)
        }
        let new = KillerPrediction(
            fixtureId: fixtureId,
            predictedOutcome: outcome,
            hitTargetPlayerId: existingTarget
        )
        context.insert(new)
        new.player = player
        new.round = round
    }

    /// Set or clear a player's Hit target for one MPG fixture (Kill Phase
    /// only). Rejects self-targeting and rejects a target already used by
    /// another of this player's Hits in the same round — the MPG-count
    /// formula guarantees a valid full assignment always exists. Returns
    /// whether the assignment was accepted (false = rejected, no-op).
    @discardableResult
    static func setHitTarget(
        player: Player,
        round: Round,
        fixtureId: Int,
        targetPlayerId: UUID?,
        context: ModelContext
    ) -> Bool {
        guard let existing = prediction(for: player, fixtureId: fixtureId, in: round) else { return false }
        if let targetPlayerId {
            guard targetPlayerId != player.id else { return false }
            let alreadyUsedElsewhere = predictions(for: player, in: round).contains {
                $0.fixtureId != fixtureId && $0.hitTargetPlayerId == targetPlayerId
            }
            guard !alreadyUsedElsewhere else { return false }
        }
        existing.hitTargetPlayerId = targetPlayerId
        return true
    }

    // MARK: - Close round

    /// Scores every `KillerPrediction` against the real results, updates the
    /// Accuracy Table, and — Build Phase — awards lives up to the cap, or —
    /// Kill Phase — resolves Hits and eliminations. Void fixtures score
    /// neither correct nor incorrect, award no life, and never land a Hit —
    /// a void is a non-event, not a fabricated result.
    ///
    /// Kill Phase resolution is a single batch pass (score everything, *then*
    /// apply all damage at once) rather than per-prediction: all predictions/
    /// Hits are locked pre-round, so a player reaching 0 lives this round
    /// must still have their own outgoing Hit register, and multiple
    /// attackers landing on the same target must all count.
    ///
    /// When a round's simultaneous zero-lives crossings would otherwise
    /// decide the game (see `applyEliminations`), the Accuracy Table (then
    /// hit-count) tiebreak resolves who wins — never a mid-game save.
    /// - Returns: `.notApplicable` if this round didn't produce a
    ///   game-deciding simultaneous elimination.
    /// - Throws: `KillerScoringError.incompleteOutcomes` if any fixture in the
    ///   round has no result in `finalOutcomes` and isn't in `voidFixtureIds`.
    @discardableResult
    static func closeRound(
        _ round: Round,
        game: Game,
        finalOutcomes: [Int: FixtureOutcome],
        voidFixtureIds: Set<Int> = [],
        context: ModelContext
    ) throws -> KillerTieOutcome {
        guard round.fixtureIds.allSatisfy({ finalOutcomes[$0] != nil || voidFixtureIds.contains($0) }) else {
            throw KillerScoringError.incompleteOutcomes
        }

        var correctCountByPlayer: [UUID: Int] = [:]
        for prediction in round.killerPredictions {
            guard let playerId = prediction.player?.id else { continue }
            if voidFixtureIds.contains(prediction.fixtureId) {
                prediction.actualOutcomeRaw = nil
                prediction.wasCorrect = nil
                prediction.hitLanded = nil
                continue
            }
            guard let actual = finalOutcomes[prediction.fixtureId] else { continue }
            prediction.actualOutcome = actual
            let correct = prediction.predictedOutcome == actual
            prediction.wasCorrect = correct
            if correct {
                correctCountByPlayer[playerId, default: 0] += 1
            }
        }

        // Accuracy Table: every correct prediction, every round, both phases.
        for player in game.players {
            guard let state = player.killerState, let correct = correctCountByPlayer[player.id] else { continue }
            state.correctPredictions += correct
        }

        let outcome: KillerTieOutcome
        switch phase(for: round, game: game) {
        case .build:
            for player in game.activePlayers {
                guard let state = player.killerState else { continue }
                let correct = correctCountByPlayer[player.id] ?? 0
                let gain = max(0, min(correct, game.killerMaxAdditionalLives - state.additionalLivesGained))
                state.lives += gain
                state.additionalLivesGained += gain
            }
            outcome = .notApplicable
        case .kill:
            resolveHits(in: round, game: game, voidFixtureIds: voidFixtureIds)
            outcome = applyEliminations(in: game)
        }

        round.status = .closed
        if game.status == .setup { game.status = .active }
        return outcome
    }

    /// Batch Hit resolution: mark every non-void, correct prediction with a
    /// Hit target as landed, credit the attacker's tiebreak counter, and
    /// accumulate damage per target — applied in one pass after every
    /// prediction in the round has been evaluated (see `closeRound`'s doc).
    private static func resolveHits(in round: Round, game: Game, voidFixtureIds: Set<Int>) {
        var damageByTarget: [UUID: Int] = [:]
        for prediction in round.killerPredictions {
            guard !voidFixtureIds.contains(prediction.fixtureId) else { continue } // hitLanded left nil, set above
            guard prediction.wasCorrect == true, let targetId = prediction.hitTargetPlayerId else {
                prediction.hitLanded = false
                continue
            }
            prediction.hitLanded = true
            if let attackerState = prediction.player?.killerState {
                attackerState.successfulHitsLanded += 1
            }
            damageByTarget[targetId, default: 0] += 1
        }
        for player in game.players {
            guard let state = player.killerState, let damage = damageByTarget[player.id] else { continue }
            state.lives -= damage
        }
    }

    /// Eliminates every active player whose lives crossed to 0 or below this
    /// round. If those zero-crossers are *everyone* still active (2+ of
    /// them) — i.e. this round would otherwise decide the game with no
    /// survivor — the Accuracy Table/hit-count tiebreak resolves who wins,
    /// auto-splitting the pot if even that leaves a tie, instead of just
    /// wiping the whole group out. Any other case (a straightforward single
    /// elimination, or several eliminated while others remain active) needs
    /// no tiebreak at all.
    @discardableResult
    private static func applyEliminations(in game: Game) -> KillerTieOutcome {
        let activeBefore = game.activePlayers
        let candidates = activeBefore.filter { ($0.killerState?.lives ?? 1) <= 0 }
        guard !candidates.isEmpty else { return .notApplicable }

        let isFinalSimultaneousElimination = candidates.count >= 2 && candidates.count == activeBefore.count
        guard isFinalSimultaneousElimination else {
            for player in candidates { player.status = .eliminated }
            if game.activePlayers.count == 1, let winner = game.activePlayers.first {
                winner.status = .winner
                game.status = .complete
            }
            return .notApplicable
        }

        let outcome = resolveSimultaneousZeros(candidates: candidates)
        switch outcome {
        case .winner(let winnerId):
            for player in candidates {
                player.status = player.id == winnerId ? .winner : .eliminated
            }
            game.status = .complete
        case .split(let winnerIds):
            for player in candidates {
                player.status = winnerIds.contains(player.id) ? .winner : .eliminated
            }
            game.status = .complete
        case .notApplicable:
            break
        }
        return outcome
    }

    /// Ranks a group of players who hit 0 lives in the same, game-deciding
    /// round: Accuracy Table (`correctPredictions`) desc, then
    /// `successfulHitsLanded` desc. A unique top scorer wins outright; a tie
    /// on both criteria auto-splits the win among the tied group.
    static func resolveSimultaneousZeros(candidates: [Player]) -> KillerTieOutcome {
        guard candidates.count >= 2 else { return .notApplicable }
        let ranked = candidates.sorted { a, b in
            let aCorrect = a.killerState?.correctPredictions ?? 0
            let bCorrect = b.killerState?.correctPredictions ?? 0
            if aCorrect != bCorrect { return aCorrect > bCorrect }
            return (a.killerState?.successfulHitsLanded ?? 0) > (b.killerState?.successfulHitsLanded ?? 0)
        }
        guard let top = ranked.first else { return .notApplicable }
        let topCorrect = top.killerState?.correctPredictions ?? 0
        let topHits = top.killerState?.successfulHitsLanded ?? 0
        let topGroup = ranked.filter {
            ($0.killerState?.correctPredictions ?? 0) == topCorrect
                && ($0.killerState?.successfulHitsLanded ?? 0) == topHits
        }
        if topGroup.count == 1 {
            return .winner(top.id)
        }
        return .split(topGroup.map(\.id))
    }
}
