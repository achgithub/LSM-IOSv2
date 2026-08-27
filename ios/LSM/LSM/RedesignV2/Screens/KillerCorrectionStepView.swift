import SwiftUI
import SwiftData

/// Killer's round-correction step — see `RoundCorrectionWizardView`'s doc
/// comment for why this mode gets a direct override rather than a replay:
/// `lives`/`correctPredictions`/`successfulHitsLanded` on `KillerPlayerState`
/// are stored cumulative counters with no per-round snapshot to unwind (and
/// `KillerScoringService.closeRound` explicitly refuses to re-run on an
/// already-closed round), so there's no safe way to "recompute" them from
/// history. The manager already knows the right current numbers — this just
/// lets them state it directly. Doesn't touch the historical per-round
/// `KillerPrediction` display; only the running totals/status.
struct KillerCorrectionStepView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let game: Game
    let player: Player

    @State private var lives = 0
    @State private var additionalLivesGained = 0
    @State private var correctPredictions = 0
    @State private var successfulHitsLanded = 0
    @State private var status: PlayerStatus = .active
    @State private var didApply = false
    @State private var loaded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: V2Theme.Spacing.section) {
                if didApply {
                    appliedCard
                } else if player.killerState == nil {
                    Text("\(player.name) has no Killer state on this game yet — nothing to correct.")
                        .font(.footnote)
                        .foregroundStyle(V2Theme.textSecondary)
                } else {
                    formCard
                }
            }
            .padding(.horizontal, V2Theme.Spacing.horizontal)
            .padding(.vertical, V2Theme.Spacing.section)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear(perform: load)
    }

    private func load() {
        guard !loaded, let state = player.killerState else { return }
        lives = state.lives
        additionalLivesGained = state.additionalLivesGained
        correctPredictions = state.correctPredictions
        successfulHitsLanded = state.successfulHitsLanded
        status = player.status
        loaded = true
    }

    private var formCard: some View {
        VStack(alignment: .leading, spacing: V2Theme.Spacing.section) {
            Text("This directly sets \(player.name)'s current totals and status — it doesn't rewrite any past round's recorded result.")
                .font(.footnote)
                .foregroundStyle(V2Theme.textSecondary)
            Card(floating: true) {
                VStack(alignment: .leading, spacing: 14) {
                    Stepper("Lives: \(lives)", value: $lives, in: 0...20)
                    Stepper("Additional lives gained: \(additionalLivesGained)", value: $additionalLivesGained, in: 0...20)
                    Stepper("Correct predictions: \(correctPredictions)", value: $correctPredictions, in: 0...100)
                    Stepper("Successful hits landed: \(successfulHitsLanded)", value: $successfulHitsLanded, in: 0...100)
                    Divider()
                    Picker("Status", selection: $status) {
                        Text("Active").tag(PlayerStatus.active)
                        Text("Eliminated").tag(PlayerStatus.eliminated)
                        Text("Winner").tag(PlayerStatus.winner)
                    }
                    .pickerStyle(.segmented)
                }
                .font(.subheadline)
            }
            TypeToConfirmButton(
                playerName: player.name,
                actionTitle: "Apply Correction",
                tint: V2Theme.Mode.killer,
                action: apply
            )
        }
    }

    private func apply() {
        guard let state = player.killerState else { return }
        state.lives = lives
        state.additionalLivesGained = additionalLivesGained
        state.correctPredictions = correctPredictions
        state.successfulHitsLanded = successfulHitsLanded
        player.status = status
        try? context.save()
        didApply = true
    }

    private var appliedCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Card(floating: true) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("\(player.name)'s totals updated", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .foregroundStyle(V2Theme.Mode.killer)
                    if game.cloudGameToken != nil {
                        Text("This correction is local only — it hasn't been pushed to the cloud yet.")
                            .font(.footnote)
                            .foregroundStyle(V2Theme.warning)
                    }
                }
            }
            PrimaryButton(title: "Done", tint: V2Theme.Mode.killer) { dismiss() }
        }
    }
}
