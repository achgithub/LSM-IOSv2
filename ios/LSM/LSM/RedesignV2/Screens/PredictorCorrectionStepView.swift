import SwiftUI
import SwiftData

/// Predictor's round-correction step — see `RoundCorrectionWizardView`'s doc
/// comment for why this mode gets the simplest treatment of the three:
/// points are summed fresh per round from stored `Prediction` rows with no
/// cross-round dependency, so fixing one round's guess and rescoring just
/// that round (`PredictorScoringService.closeRound`, safe to call again on
/// an already-closed round — no re-entry guard, unlike Killer's) is
/// sufficient. No forward replay, no conflict chain.
struct PredictorCorrectionStepView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let game: Game
    let player: Player

    @State private var selectedRound: Round?
    @State private var data: LeagueData?
    @State private var edits: [Int: (home: Int, away: Int)] = [:]
    @State private var didApply = false
    @State private var applyError: String?

    private var closedRounds: [Round] {
        game.rounds.filter { $0.status == .closed }.sorted { $0.roundNumber > $1.roundNumber }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: V2Theme.Spacing.section) {
                if didApply {
                    appliedCard
                } else if let round = selectedRound {
                    correctionCard(for: round)
                } else {
                    roundPicker
                }
            }
            .padding(.horizontal, V2Theme.Spacing.horizontal)
            .padding(.vertical, V2Theme.Spacing.section)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { data = try? await LeagueData.load(for: game.leagues) }
    }

    private var roundPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Which matchday needs a corrected prediction for \(player.name)?")
                .font(.footnote)
                .foregroundStyle(V2Theme.textSecondary)
            Card(floating: true) {
                VStack(spacing: 6) {
                    if closedRounds.isEmpty {
                        Text("No closed matchdays yet.")
                            .font(.footnote)
                            .foregroundStyle(V2Theme.textSecondary)
                    } else {
                        ForEach(closedRounds, id: \.id) { round in
                            Button {
                                selectedRound = round
                                seedEdits(for: round)
                            } label: {
                                HStack {
                                    Text("Matchday \(round.roundNumber)")
                                        .font(V2Theme.Typography.rowTitle)
                                        .foregroundStyle(V2Theme.textPrimary)
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

    private func fixtureName(_ id: Int) -> String {
        guard let match = data?.matches.first(where: { $0.id == id }) else { return "Fixture \(id)" }
        let home = data?.teamsById[match.homeTeamId]?.shortName ?? "Home"
        let away = data?.teamsById[match.awayTeamId]?.shortName ?? "Away"
        return "\(home) v \(away)"
    }

    private func seedEdits(for round: Round) {
        var seeded: [Int: (home: Int, away: Int)] = [:]
        for prediction in PredictorScoringService.predictions(for: player, in: round) {
            seeded[prediction.fixtureId] = (prediction.predictedHome, prediction.predictedAway)
        }
        edits = seeded
    }

    private func correctionCard(for round: Round) -> some View {
        VStack(alignment: .leading, spacing: V2Theme.Spacing.section) {
            Text("Correct \(player.name)'s prediction for Matchday \(round.roundNumber), then recalculate — only this matchday's points change.")
                .font(.footnote)
                .foregroundStyle(V2Theme.textSecondary)
            Card(floating: true) {
                VStack(spacing: 12) {
                    ForEach(round.fixtureIds, id: \.self) { fixtureId in
                        fixtureRow(fixtureId: fixtureId)
                    }
                }
            }
            if let applyError {
                Text(applyError)
                    .font(.footnote)
                    .foregroundStyle(V2Theme.danger)
            }
            TypeToConfirmButton(
                playerName: player.name,
                actionTitle: "Recalculate Matchday \(round.roundNumber)",
                tint: V2Theme.Mode.predictor,
                action: { apply(to: round) }
            )
        }
    }

    private func fixtureRow(fixtureId: Int) -> some View {
        let binding = Binding<(home: Int, away: Int)>(
            get: { edits[fixtureId] ?? (0, 0) },
            set: { edits[fixtureId] = $0 }
        )
        return VStack(alignment: .leading, spacing: 6) {
            Text(fixtureName(fixtureId))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(V2Theme.textPrimary)
            HStack(spacing: 16) {
                Stepper("Home: \(binding.wrappedValue.home)", value: Binding(
                    get: { binding.wrappedValue.home },
                    set: { binding.wrappedValue.home = $0 }
                ), in: 0...20)
                Stepper("Away: \(binding.wrappedValue.away)", value: Binding(
                    get: { binding.wrappedValue.away },
                    set: { binding.wrappedValue.away = $0 }
                ), in: 0...20)
            }
            .font(.footnote)
        }
        .padding(.vertical, 4)
    }

    private func apply(to round: Round) {
        applyError = nil
        for fixtureId in round.fixtureIds {
            guard let edit = edits[fixtureId] else { continue }
            PredictorScoringService.setPrediction(
                player: player, round: round, fixtureId: fixtureId,
                home: edit.home, away: edit.away, context: context
            )
        }

        // Actual scores are shared across every player's row for this round —
        // pull them from whichever prediction still has them (any player,
        // any fixture), same fixtures the round was originally closed with.
        var finalScores: [Int: (home: Int, away: Int)] = [:]
        for prediction in round.predictions {
            guard let actualHome = prediction.actualHome, let actualAway = prediction.actualAway else { continue }
            finalScores[prediction.fixtureId] = (actualHome, actualAway)
        }
        // `voidFixtureIds` itself isn't stored anywhere after a round closes —
        // but the round already closed successfully once, so `closeRound`'s own
        // guard (every fixture needs a score OR a void flag) means any fixture
        // with no recorded score here must have been void back then too.
        let voidFixtureIds = Set(round.fixtureIds).subtracting(finalScores.keys)

        do {
            try PredictorScoringService.closeRound(round, game: game, finalScores: finalScores, voidFixtureIds: voidFixtureIds, context: context)
            try context.save()
            didApply = true
        } catch {
            applyError = error.localizedDescription
        }
    }

    private var appliedCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Card(floating: true) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Matchday recalculated", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .foregroundStyle(V2Theme.Mode.predictor)
                    if game.cloudGameToken != nil {
                        Text("This correction is local only — it hasn't been pushed to the cloud yet.")
                            .font(.footnote)
                            .foregroundStyle(V2Theme.warning)
                    }
                }
            }
            PrimaryButton(title: "Done", tint: V2Theme.Mode.predictor) { dismiss() }
        }
    }
}
