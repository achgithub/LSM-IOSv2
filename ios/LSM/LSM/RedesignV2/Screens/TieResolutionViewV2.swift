import SwiftUI

/// Card restyle of `TieResolutionView` — shown when everyone still active
/// was eliminated in the same round. Same three resolutions
/// (`GameLogicService.apply(_:game:)` calls unchanged), copied rather than
/// shared.
struct TieResolutionViewV2: View {
    @Environment(\.dismiss) private var dismiss
    let game: Game
    let tiedPlayers: [Player]
    let onResolved: (RoundType?) -> Void

    private var tiedIds: [UUID] { tiedPlayers.map(\.id) }

    private var poolExhausted: Bool {
        GameEngine.poolExhausted(
            usedTeamCounts: tiedPlayers.map { GameLogicService.usedTeamIds(for: $0).count },
            totalTeams: game.totalTeamCount
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: V2Theme.Spacing.section) {
                    Card(floating: true) {
                        Text("Everyone still in was eliminated this round — no clear winner. How should it resolve?")
                            .font(.subheadline)
                            .foregroundStyle(V2Theme.textPrimary)
                    }

                    Card(floating: true) {
                        VStack(spacing: 10) {
                            resolutionButton(
                                title: "Split the win",
                                detail: "Joint winners — the prize is divided."
                            ) { resolve(.winners(tiedIds)) }

                            resolutionButton(title: "Roll the week", detail: rollDetail) {
                                resolve(.rollWeek(tiedIds: tiedIds, resetPool: poolExhausted))
                            }

                            resolutionButton(title: "Everyone back in", detail: everyoneBackInDetail) {
                                resolve(.everyoneBackIn(allIds: game.players.map(\.id)))
                            }
                        }
                    }
                }
                .padding(.horizontal, V2Theme.Spacing.horizontal)
                .padding(.vertical, V2Theme.Spacing.section)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .v2TrophyRoomScene()
            .v2FloatingHeader("No Clear Winner", showBack: false) {
                Button("Cancel") { dismiss() }
                    .foregroundStyle(V2Theme.textSecondary)
            }
        }
        .interactiveDismissDisabled()
    }

    private var rollDetail: String {
        let base = AppString("The \(tiedPlayers.count) tied players carry forward and replay.")
        return poolExhausted
            ? base + " " + AppString("Their team pool resets — all teams open again.")
            : base
    }

    private var everyoneBackInDetail: String {
        AppString("All \(game.players.count) players reinstated, picks reset.")
    }

    private func resolutionButton(title: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline).foregroundStyle(V2Theme.textPrimary)
                    Text(detail).font(.caption).foregroundStyle(V2Theme.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(V2Theme.textSecondary)
            }
            .padding(12)
            .background(V2Theme.pillBackground, in: RoundedRectangle(cornerRadius: V2Theme.Radius.row, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func resolve(_ outcome: TieOutcome) {
        let followUp = GameLogicService.apply(outcome, game: game)
        onResolved(followUp)
        dismiss()
    }
}
