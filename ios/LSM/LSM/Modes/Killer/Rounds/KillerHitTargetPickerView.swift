import SwiftUI
import SwiftData

/// Kill Phase only: picks which opponent one MPG's Hit targets. Net new — no
/// reuse candidate in LMS/Predictor (neither has adversarial targeting).
/// Already-used opponents (by the same player, this round) are excluded from
/// the list so a duplicate target can't be picked in the first place, rather
/// than merely greyed out. At exactly 2 active players there's only one
/// possible opponent, so the picker hides itself and auto-assigns it.
struct KillerHitTargetPickerView: View {
    @Environment(\.modelContext) private var context
    let game: Game
    let player: Player
    let round: Round
    let fixtureId: Int

    private var existing: KillerPrediction? {
        KillerScoringService.prediction(for: player, fixtureId: fixtureId, in: round)
    }

    private var otherActivePlayers: [Player] {
        game.players.filter { $0.status == .active && $0.id != player.id }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Opponents already targeted by this player's *other* Hits this round —
    /// excluded here so the distinct-opponent constraint holds by construction.
    private var usedElsewhere: Set<UUID> {
        Set(
            KillerScoringService.predictions(for: player, in: round)
                .filter { $0.fixtureId != fixtureId }
                .compactMap(\.hitTargetPlayerId)
        )
    }

    private var availableTargets: [Player] {
        otherActivePlayers.filter { !usedElsewhere.contains($0.id) }
    }

    var body: some View {
        Group {
            if otherActivePlayers.count <= 1 {
                EmptyView()
            } else {
                Picker("Hit target", selection: targetBinding) {
                    Text("—").tag(UUID?.none)
                    ForEach(availableTargets) { opponent in
                        Text(opponent.name).tag(UUID?.some(opponent.id))
                    }
                }
                .pickerStyle(.menu)
                .disabled(existing == nil)
            }
        }
        .onAppear { autoAssignIfOnlyOpponent() }
    }

    private var targetBinding: Binding<UUID?> {
        Binding(
            get: { existing?.hitTargetPlayerId },
            set: { newValue in
                KillerScoringService.setHitTarget(
                    player: player, round: round, fixtureId: fixtureId, targetPlayerId: newValue, context: context
                )
            }
        )
    }

    /// When there's only one possible opponent, there's no real choice to
    /// make — assign it automatically rather than showing a one-item picker.
    private func autoAssignIfOnlyOpponent() {
        guard otherActivePlayers.count == 1, existing?.hitTargetPlayerId == nil,
              let onlyOpponent = otherActivePlayers.first else { return }
        KillerScoringService.setHitTarget(
            player: player, round: round, fixtureId: fixtureId, targetPlayerId: onlyOpponent.id, context: context
        )
    }
}
