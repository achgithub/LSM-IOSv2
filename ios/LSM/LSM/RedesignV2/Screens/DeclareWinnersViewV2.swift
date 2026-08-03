import SwiftUI
import SwiftData

/// Card restyle of `DeclareWinnersView` — manager override (spec §13c.8):
/// declare winner(s) at any round close, regardless of the configured tie
/// rule. Same `apply()` logic, copied rather than shared.
struct DeclareWinnersViewV2: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(Entitlements.self) private var entitlements
    let game: Game
    let onDone: () -> Void

    @AppStorage("pwaSubmissionsEnabled") private var pwaSubmissionsEnabled = false
    @AppStorage(ManagerSettings.nameKey) private var managerName = ""
    @State private var selection: Set<UUID> = []

    private var sortedPlayers: [Player] {
        game.players.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: V2Theme.Spacing.section) {
                    Card {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(title: "Select the winner(s)")
                            VStack(spacing: 6) {
                                ForEach(sortedPlayers, id: \.id) { player in
                                    Button {
                                        toggle(player.id)
                                    } label: {
                                        HStack {
                                            Text(player.name).foregroundStyle(V2Theme.textPrimary)
                                            if player.status != .active {
                                                Text(player.status.label)
                                                    .font(.caption2).foregroundStyle(V2Theme.textSecondary)
                                            }
                                            Spacer()
                                            if selection.contains(player.id) {
                                                Image(systemName: "checkmark").foregroundStyle(V2Theme.Mode.lms)
                                            }
                                        }
                                        .padding(10)
                                        .background(
                                            selection.contains(player.id) ? V2Theme.highlightBackground : V2Theme.pillBackground,
                                            in: RoundedRectangle(cornerRadius: V2Theme.Radius.row, style: .continuous)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    Text("Selected players win; everyone else is eliminated and the game ends.")
                        .font(.caption).foregroundStyle(V2Theme.textTertiary)
                }
                .padding(.horizontal, V2Theme.Spacing.horizontal)
                .padding(.vertical, V2Theme.Spacing.section)
            }
            .background(V2Theme.background.ignoresSafeArea())
            .navigationTitle("Declare Winner(s)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Declare") { apply() }.disabled(selection.isEmpty)
                }
            }
        }
    }

    private func toggle(_ id: UUID) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }

    private func apply() {
        GameLogicService.apply(.winners(Array(selection)), game: game)
        try? context.save()
        if entitlements.canUseCloud, pwaSubmissionsEnabled, game.cloudGameToken != nil {
            let name = managerName
            Task { try? await PWARoundPusher.pushLMSOrPredictor(game: game, round: nil, managerName: name, context: context) }
        }
        onDone()
        dismiss()
    }
}
