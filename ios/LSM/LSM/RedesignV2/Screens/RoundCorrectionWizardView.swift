import SwiftUI

/// Retroactively fix one player's history for one past round — for when a
/// manager notices, after the fact, that they mis-recorded a pick/prediction
/// or a round's close was wrong. Deliberately buried in the per-game header's
/// export `Menu` (`V2GameHeaderActions`) rather than a first-class button —
/// this is a rare, support-style operation, not a casual one, and per the
/// design discussion (see `docs/error-correction-wizard-design.md`) the
/// friction of having to go looking for it is intentional.
///
/// Mode-specific from the player picker onward, because each mode's "current
/// truth" is derived differently and needs a different fix:
/// - LMS: team choice is a shared pool across rounds (`usedTeamIds`), so
///   fixing one round can require freeing a team a later round is holding —
///   see `LMSCorrectionChainView`/`LMSCorrectionChain`.
/// - Predictor: points are summed fresh per round with no cross-round
///   dependency, so fixing one round's prediction and rescoring just that
///   round is sufficient — see `PredictorCorrectionStepView`.
/// - Killer: `lives`/`correctPredictions`/`successfulHitsLanded` are stored
///   cumulative counters with no per-round snapshot to unwind, so this is a
///   direct override of the current totals/status, not a replay — see
///   `KillerCorrectionStepView`.
struct RoundCorrectionWizardView: View {
    @Environment(\.dismiss) private var dismiss
    let game: Game

    @State private var selectedPlayer: Player?

    private var sortedPlayers: [Player] {
        game.players.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let selectedPlayer {
                    modeStep(for: selectedPlayer)
                } else {
                    playerPicker
                }
            }
            .v2FloatingHeader(selectedPlayer == nil ? "Fix a Player's History" : selectedPlayer!.name, showBack: selectedPlayer != nil) {
                Button("Cancel") { dismiss() }
                    .foregroundStyle(V2Theme.textSecondary)
            }
            .v2TrophyRoomScene()
        }
    }

    private var playerPicker: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: V2Theme.Spacing.section) {
                Text("Which player's history needs fixing? This corrects one player's record for one past round — run it again separately for anyone else.")
                    .font(.footnote)
                    .foregroundStyle(V2Theme.textSecondary)
                Card(floating: true) {
                    VStack(spacing: 6) {
                        if sortedPlayers.isEmpty {
                            Text("No players in this game yet.")
                                .font(.footnote)
                                .foregroundStyle(V2Theme.textSecondary)
                        } else {
                            ForEach(sortedPlayers) { player in
                                Button {
                                    selectedPlayer = player
                                } label: {
                                    HStack {
                                        Text(player.name)
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
            .padding(.horizontal, V2Theme.Spacing.horizontal)
            .padding(.vertical, V2Theme.Spacing.section)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func modeStep(for player: Player) -> some View {
        switch game.mode {
        case .lms: LMSCorrectionChainView(game: game, player: player)
        case .predictor: PredictorCorrectionStepView(game: game, player: player)
        case .killer: KillerCorrectionStepView(game: game, player: player)
        }
    }
}

/// Shared friction gate for every mode's correction flow — require the
/// player's name typed back before the action unlocks. Not a plain "are you
/// sure" alert: the point (per the design discussion) is forcing the manager
/// to actually read whatever diff/summary sits above this, not just tap
/// through a confirmation reflexively.
struct TypeToConfirmButton: View {
    let playerName: String
    let actionTitle: String
    var tint: Color = V2Theme.accent
    let action: () -> Void
    @State private var typed = ""

    private var matches: Bool {
        !playerName.isEmpty
            && typed.trimmingCharacters(in: .whitespacesAndNewlines).localizedCaseInsensitiveCompare(playerName) == .orderedSame
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Type \"\(playerName)\" to confirm")
                .font(.caption)
                .foregroundStyle(V2Theme.textSecondary)
            TextField(playerName, text: $typed)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .padding(12)
                .v2FloatingCard(cornerRadius: V2Theme.Radius.row)
            PrimaryButton(title: actionTitle, isEnabled: matches, tint: tint, action: action)
        }
    }
}
