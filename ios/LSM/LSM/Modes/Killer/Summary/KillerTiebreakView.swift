import SwiftUI
import SwiftData

/// Surfaces a `KillerTieOutcome.stillTied` — a round's simultaneous
/// zero-lives crossings that even the Accuracy Table + hit-count tiebreak
/// couldn't separate. Not auto-resolved: the manager either declares one
/// outright winner or splits the pot across everyone still selected,
/// patterned after LMS's manual tie-resolution surface (different options,
/// same "manager makes the final call" shape).
struct KillerTiebreakView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(Entitlements.self) private var entitlements
    let game: Game
    let candidates: [Player]

    @AppStorage("pwaSubmissionsEnabled") private var pwaSubmissionsEnabled = false
    @AppStorage(ManagerSettings.nameKey) private var managerName = ""
    /// Selected winner(s) — starts empty, manager must pick at least one.
    @State private var selectedWinnerIds: Set<UUID> = []

    private var sortedCandidates: [Player] {
        candidates.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("These players tied on both the Accuracy Table and hit count — pick the winner, or select several to split the pot.")
                        .foregroundStyle(.secondary)
                }
                Section("Tied players") {
                    ForEach(sortedCandidates) { player in
                        Button {
                            toggle(player.id)
                        } label: {
                            HStack {
                                Text(player.name).foregroundStyle(.primary)
                                Spacer()
                                LabeledContent(
                                    "Accuracy", value: "\(player.killerState?.correctPredictions ?? 0)"
                                )
                                .font(.caption).foregroundStyle(.secondary)
                                if selectedWinnerIds.contains(player.id) {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
                                } else {
                                    Image(systemName: "circle").foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Resolve Tie")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Confirm") { confirm() }
                        .disabled(selectedWinnerIds.isEmpty)
                }
            }
        }
        .interactiveDismissDisabled()
    }

    private func toggle(_ id: UUID) {
        if selectedWinnerIds.contains(id) { selectedWinnerIds.remove(id) } else { selectedWinnerIds.insert(id) }
    }

    private func confirm() {
        KillerScoringService.applyTiebreakDecision(candidates: candidates, winnerIds: selectedWinnerIds, game: game)
        try? context.save()
        // The game just completed with no further round to open — same
        // reasoning as `KillerResultsEntryView`'s single-survivor path.
        if entitlements.canUseCloud, pwaSubmissionsEnabled, game.cloudGameToken != nil {
            let name = managerName
            Task { try? await PWARoundPusher.pushKiller(game: game, round: nil, managerName: name, context: context) }
        }
        dismiss()
    }
}
