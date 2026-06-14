import Foundation

/// Pure game-logic engine (port of the PWA's gameLogic.ts, spec §6.4/§6.5/§13c).
/// All methods are pure functions over the value types in EngineTypes.swift.
nonisolated enum GameEngine {

    // MARK: - Auto-assign (§6.4)

    /// Assign one team to each active player when the deadline passes.
    /// Standings-aware: the bottom-of-table available team is assigned first.
    /// Each player is independent — two players may receive the same team.
    /// Returns a map of player id → assigned team id. A player with no eligible
    /// team (repeats off and all fixture teams used) is omitted.
    static func autoAssign(_ input: AutoAssignInput) -> [UUID: Int] {
        let standingsKnown = input.fixtureTeams.contains { $0.position != nil }
        var assignments: [UUID: Int] = [:]
        for player in input.players {
            let ordered = orderedAvailableTeams(
                fixtureTeams: input.fixtureTeams,
                used: player.usedTeamIds,
                allowRepeats: input.allowRepeats,
                standingsKnown: standingsKnown
            )
            if let first = ordered.first {
                assignments[player.id] = first.id
            }
        }
        return assignments
    }

    /// The fixture teams ordered by assignment priority for one player.
    /// - Unused teams first; if repeats are allowed, used teams follow at the
    ///   bottom; if not, used teams are excluded entirely.
    /// - Within a group: by league position descending (position 20 / bottom
    ///   first) when standings are known, else alphabetically by name.
    static func orderedAvailableTeams(
        fixtureTeams: [TeamRef],
        used: Set<Int>,
        allowRepeats: Bool,
        standingsKnown: Bool
    ) -> [TeamRef] {
        let unused = fixtureTeams.filter { !used.contains($0.id) }
        let usedTeams = fixtureTeams.filter { used.contains($0.id) }

        func prioritised(_ teams: [TeamRef]) -> [TeamRef] {
            guard standingsKnown else {
                return teams.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            }
            return teams.sorted { lhs, rhs in
                switch (lhs.position, rhs.position) {
                case let (l?, r?): return l > r            // bottom of table first
                case (nil, _?): return false               // unknown positions last
                case (_?, nil): return true
                case (nil, nil): return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
            }
        }

        return allowRepeats ? prioritised(unused) + prioritised(usedTeams) : prioritised(unused)
    }

    // MARK: - Eliminations (§6.5)

    /// A loss eliminates; win/draw/postponed survive. Unresolved (nil) is treated
    /// as surviving — a round should not be closed before results are known.
    static func computeEliminations(picks: [PickOutcome]) -> EliminationResult {
        var eliminated: [UUID] = []
        var surviving: [UUID] = []
        for pick in picks {
            switch pick.result {
            case .loss:
                eliminated.append(pick.playerId)
            case .win, .draw, .postponed, .none:
                surviving.append(pick.playerId)
            }
        }
        return EliminationResult(eliminatedPlayerIds: eliminated, survivingPlayerIds: surviving)
    }

    /// True when everyone still active was eliminated in the same round (§13c.4).
    static func isAllEliminated(activeBefore: Int, eliminatedThisRound: Int) -> Bool {
        activeBefore > 0 && eliminatedThisRound >= activeBefore
    }

    /// A pick is "weak" if the team was in the bottom half of the table when
    /// assigned (§13c.5) — used as the longevity secondary tiebreaker.
    static func isWeakPick(position: Int?, teamsCount: Int) -> Bool {
        guard let position, teamsCount > 0 else { return false }
        return position > teamsCount / 2
    }

    // MARK: - Tie / all-eliminated resolution (§13c)

    /// Resolve the all-eliminated tie for the configured rule.
    /// `tiedPlayers` are those active immediately before the tie round closed.
    /// `allPlayerIds` is every player in the game (for full reset).
    static func resolveTie(
        rule: TieRule,
        tiedPlayers: [TiePlayer],
        allPlayerIds: [UUID]
    ) -> TieOutcome {
        let tiedIds = tiedPlayers.map(\.id)
        switch rule {
        case .split:
            return .jointWinners(tiedIds)

        case .rolloverRound:
            var usedToAdd: [UUID: Int] = [:]
            for player in tiedPlayers where player.thisRoundTeamId != nil {
                usedToAdd[player.id] = player.thisRoundTeamId
            }
            return .rollover(reinstated: tiedIds, usedTeamToAdd: usedToAdd)

        case .fullReset:
            return .fullReset(reinstatedAll: allPlayerIds)

        case .suddenDeath:
            return .suddenDeathPlayoff(tiedIds)

        case .longevity:
            return resolveLongevity(tiedPlayers)
        }
    }

    /// Most rounds survived wins; tiebreak on fewest weak picks; if still tied,
    /// fall back to a split (§13c.2 rule 5 edge case).
    private static func resolveLongevity(_ players: [TiePlayer]) -> TieOutcome {
        guard !players.isEmpty else { return .jointWinners([]) }

        let maxRounds = players.map(\.roundsSurvived).max() ?? 0
        let topByRounds = players.filter { $0.roundsSurvived == maxRounds }
        if topByRounds.count == 1 {
            return .singleWinner(topByRounds[0].id, reason: "longevity")
        }

        let minWeak = topByRounds.map(\.weakPicks).min() ?? 0
        let topByWeak = topByRounds.filter { $0.weakPicks == minWeak }
        if topByWeak.count == 1 {
            return .singleWinner(topByWeak[0].id, reason: "fewest weak picks")
        }

        return .jointWinners(topByWeak.map(\.id))
    }

    // MARK: - Manager override

    /// Manager manually declares the winner(s) and completes the game, regardless
    /// of the configured tie rule. Available at any round close (one obvious
    /// survivor, an off-app agreement, a dispute, abandoning the game, etc.).
    static func declareWinners(_ playerIds: [UUID]) -> TieOutcome {
        .manualWinners(playerIds)
    }
}
