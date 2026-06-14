import SwiftUI

/// Shown when everyone still active was eliminated in the same round (§13c.4).
/// Applies the game's configured tie rule, or lets the manager declare winner(s).
struct TieResolutionView: View {
    @Environment(\.dismiss) private var dismiss
    let game: Game
    let round: Round
    let tiedPlayers: [Player]
    /// Reports the resolution: a follow-up round type (`.rollover`/`.playoff`) to
    /// open next, or `nil` when the game is now complete.
    let onResolved: (RoundType?) -> Void

    @State private var manualSelection: Set<UUID> = []

    private var sortedTied: [Player] {
        tiedPlayers.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Everyone still in was eliminated this round. Resolve it:")
                        .font(.subheadline)
                }

                Section("Configured rule") {
                    Text(game.tieRule.label).bold()
                    Text(game.tieRule.detail).font(.caption).foregroundStyle(.secondary)
                    Button("Apply “\(game.tieRule.label)”") { applyConfigured() }
                }

                Section("Or declare winner(s) manually") {
                    ForEach(sortedTied, id: \.id) { player in
                        Button {
                            toggle(player.id)
                        } label: {
                            HStack {
                                Text(player.name).foregroundStyle(.primary)
                                Spacer()
                                if manualSelection.contains(player.id) {
                                    Image(systemName: "checkmark").foregroundStyle(.blue)
                                }
                            }
                        }
                    }
                    Button("Declare selected as winner(s)") { applyManual() }
                        .disabled(manualSelection.isEmpty)
                }
            }
            .navigationTitle("Round Tie")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Later") { dismiss() } }
            }
        }
        .interactiveDismissDisabled()
    }

    private func toggle(_ id: UUID) {
        if manualSelection.contains(id) { manualSelection.remove(id) } else { manualSelection.insert(id) }
    }

    private func applyConfigured() {
        let tiePlayers = GameLogicService.tiePlayers(from: tiedPlayers, round: round)
        let outcome = GameEngine.resolveTie(
            rule: game.tieRule,
            tiedPlayers: tiePlayers,
            allPlayerIds: game.players.map(\.id)
        )
        GameLogicService.apply(outcome, game: game)
        finish(followUp: followUpRound(for: outcome))
    }

    private func applyManual() {
        GameLogicService.apply(GameEngine.declareWinners(Array(manualSelection)), game: game)
        finish(followUp: nil)
    }

    /// Resolutions that reinstate players need a fresh round opened next.
    private func followUpRound(for outcome: TieOutcome) -> RoundType? {
        switch outcome {
        case .rollover: return .rollover
        case .suddenDeathPlayoff: return .playoff
        case .fullReset: return .normal
        case .jointWinners, .singleWinner, .manualWinners: return nil
        }
    }

    private func finish(followUp: RoundType?) {
        onResolved(followUp)
        dismiss()
    }
}
