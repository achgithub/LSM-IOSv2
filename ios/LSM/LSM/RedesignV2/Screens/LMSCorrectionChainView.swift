import SwiftUI
import SwiftData

/// LMS's round-correction step — see `RoundCorrectionWizardView`'s doc
/// comment and `LMSCorrectionChain`'s doc comment for the mechanism. Walks
/// the manager through: pick the target round to fix, pick the corrected
/// team; if that team's already used by a later closed round, resolve that
/// round next (recursing outward, most-recent-conflict-first); once the
/// whole chain is conflict-free, preview every round that will change, then
/// type-to-confirm and apply.
struct LMSCorrectionChainView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let game: Game
    let player: Player

    @State private var data: LeagueData?
    @State private var targetRound: Round?
    /// The chain's open stack — target round at the bottom; a round pushed
    /// on top is one that turned out to be blocking whatever's below it and
    /// needs its own correction chosen before we can go back down.
    @State private var chainRoundNumbers: [Int] = []
    @State private var roundsByNumber: [Int: Round] = [:]
    /// Round number → chosen (teamId, fixtureId) for every round in the
    /// chain, resolved or not.
    @State private var chosenTeam: [Int: (teamId: Int, fixtureId: Int?)] = [:]
    /// Round number → new team id, for rounds fully resolved (no remaining
    /// conflict) — see `LMSCorrectionChain`'s doc comment on why this is a
    /// team-id map, not just a set of round numbers.
    @State private var resolved: [Int: Int] = [:]
    @State private var showingPreview = false
    @State private var didApply = false

    private var closedRounds: [Round] {
        game.rounds.filter { $0.status == .closed }.sorted { $0.roundNumber > $1.roundNumber }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: V2Theme.Spacing.section) {
                if didApply {
                    appliedCard
                } else if showingPreview {
                    previewCard
                } else if let currentRoundNumber = chainRoundNumbers.last, let round = roundsByNumber[currentRoundNumber] {
                    teamPickCard(for: round, isTarget: currentRoundNumber == targetRound?.roundNumber)
                } else {
                    targetRoundPicker
                }
            }
            .padding(.horizontal, V2Theme.Spacing.horizontal)
            .padding(.vertical, V2Theme.Spacing.section)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { data = try? await LeagueData.load(for: game.leagues) }
    }

    // MARK: - Step 1: target round

    private var targetRoundPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Which round has \(player.name)'s wrong pick?")
                .font(.footnote)
                .foregroundStyle(V2Theme.textSecondary)
            Card(floating: true) {
                VStack(spacing: 6) {
                    if closedRounds.isEmpty {
                        Text("No closed rounds yet.")
                            .font(.footnote)
                            .foregroundStyle(V2Theme.textSecondary)
                    } else {
                        ForEach(closedRounds, id: \.id) { round in
                            Button {
                                begin(with: round)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Round \(round.roundNumber)")
                                            .font(V2Theme.Typography.rowTitle)
                                            .foregroundStyle(V2Theme.textPrimary)
                                        if let pick = GameLogicService.pick(for: player, in: round) {
                                            Text("Recorded: \(teamName(pick.teamId))")
                                                .font(.caption)
                                                .foregroundStyle(V2Theme.textSecondary)
                                        } else {
                                            Text("No pick recorded")
                                                .font(.caption)
                                                .foregroundStyle(V2Theme.warning)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(V2Theme.textSecondary)
                                }
                                .padding(10)
                                .background(V2Theme.pillBackground, in: RoundedRectangle(cornerRadius: V2Theme.Radius.row, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func begin(with round: Round) {
        targetRound = round
        roundsByNumber[round.roundNumber] = round
        chainRoundNumbers = [round.roundNumber]
    }

    // MARK: - Step 2: team pick per round in the chain

    private func teamName(_ id: Int) -> String {
        data?.teamsById[id]?.shortName ?? data?.teamsById[id]?.name ?? "Team \(id)"
    }

    private func teamPickCard(for round: Round, isTarget: Bool) -> some View {
        let eligible = LMSCorrectionChain.eligibleTeams(for: player, round: round, game: game, data: data, resolved: resolved)
        return VStack(alignment: .leading, spacing: V2Theme.Spacing.section) {
            if isTarget {
                Text("What should \(player.name) have picked in Round \(round.roundNumber)?")
                    .font(.footnote)
                    .foregroundStyle(V2Theme.textSecondary)
            } else {
                Text("Round \(round.roundNumber) is already using that team — what did \(player.name) actually want that week instead?")
                    .font(.footnote)
                    .foregroundStyle(V2Theme.warning)
            }
            Card(floating: true) {
                VStack(spacing: 6) {
                    if eligible.isEmpty {
                        Text("No eligible teams for this round.")
                            .font(.footnote)
                            .foregroundStyle(V2Theme.textSecondary)
                    } else {
                        ForEach(eligible, id: \.pickKey) { team in
                            Button {
                                choose(team: team, for: round)
                            } label: {
                                HStack(spacing: 10) {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(team.name).foregroundStyle(V2Theme.textPrimary)
                                        if let opponent = team.opponentName {
                                            Text("vs \(opponent)").font(.caption).foregroundStyle(V2Theme.textSecondary)
                                        }
                                    }
                                    Spacer()
                                }
                                .padding(10)
                                .background(V2Theme.pillBackground, in: RoundedRectangle(cornerRadius: V2Theme.Radius.row, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func choose(team: TeamRef, for round: Round) {
        chosenTeam[round.roundNumber] = (team.id, team.fixtureId)
        advance()
    }

    /// Resolves as much of the chain as possible without further user input:
    /// checks the top-of-stack round's chosen team for a conflict with a
    /// later round; if blocked, pushes that round (needs its own choice —
    /// stop and wait); otherwise finalizes the top round and re-checks the
    /// one below it, since it may now be conflict-free.
    private func advance() {
        while let currentNumber = chainRoundNumbers.last {
            guard let choice = chosenTeam[currentNumber] else { return }
            if let blocking = LMSCorrectionChain.blockingRound(for: player, teamId: choice.teamId, targetRoundNumber: currentNumber, resolved: resolved),
               !chainRoundNumbers.contains(blocking.roundNumber) {
                roundsByNumber[blocking.roundNumber] = blocking
                chainRoundNumbers.append(blocking.roundNumber)
                return
            }
            resolved[currentNumber] = choice.teamId
            chainRoundNumbers.removeLast()
        }
        showingPreview = true
    }

    // MARK: - Step 3: preview + confirm

    private var resolvedSteps: [LMSCorrectionChain.Step] {
        resolved.compactMap { roundNumber, newTeamId -> LMSCorrectionChain.Step? in
            guard let round = roundsByNumber[roundNumber], let choice = chosenTeam[roundNumber] else { return nil }
            let outcome = LMSCorrectionChain.resolve(teamId: newTeamId, fixtureId: choice.fixtureId, round: round, game: game, data: data)
            return LMSCorrectionChain.Step(
                round: round,
                oldTeamId: GameLogicService.pick(for: player, in: round)?.teamId,
                newTeamId: newTeamId,
                newFixtureId: choice.fixtureId,
                newResult: outcome.result,
                survivesRound: outcome.survives
            )
        }
        .sorted { $0.round.roundNumber < $1.round.roundNumber }
    }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: V2Theme.Spacing.section) {
            Text("This changes \(resolvedSteps.count == 1 ? "1 round" : "\(resolvedSteps.count) rounds") for \(player.name). Nothing else is touched.")
                .font(.footnote)
                .foregroundStyle(V2Theme.textSecondary)
            Card(floating: true) {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(resolvedSteps, id: \.round.roundNumber) { step in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Round \(step.round.roundNumber)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(V2Theme.textPrimary)
                            Text(step.oldTeamId.map { "\(teamName($0)) → \(teamName(step.newTeamId))" } ?? "No pick → \(teamName(step.newTeamId))")
                                .font(.caption)
                                .foregroundStyle(V2Theme.textSecondary)
                            if let result = step.newResult {
                                Text("Result: \(String(describing: result).capitalized) — \(step.survivesRound ? "survives" : "eliminated")")
                                    .font(.caption)
                                    .foregroundStyle(step.survivesRound ? V2Theme.accent : V2Theme.danger)
                            } else {
                                Text("Result unknown — fixture data not cached")
                                    .font(.caption)
                                    .foregroundStyle(V2Theme.warning)
                            }
                        }
                    }
                }
            }
            TypeToConfirmButton(
                playerName: player.name,
                actionTitle: "Apply Correction",
                tint: V2Theme.Mode.lms,
                action: apply
            )
        }
    }

    private func apply() {
        LMSCorrectionChain.apply(resolvedSteps, player: player, context: context)
        try? context.save()
        didApply = true
    }

    private var appliedCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Card(floating: true) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("\(player.name)'s history corrected", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .foregroundStyle(V2Theme.Mode.lms)
                    if game.cloudGameToken != nil {
                        Text("This correction is local only — it hasn't been pushed to the cloud yet.")
                            .font(.footnote)
                            .foregroundStyle(V2Theme.warning)
                    }
                }
            }
            PrimaryButton(title: "Done", tint: V2Theme.Mode.lms) { dismiss() }
        }
    }
}
