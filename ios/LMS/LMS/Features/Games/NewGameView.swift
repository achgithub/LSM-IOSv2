import SwiftUI
import SwiftData

/// Create-game form (spec §6.1). Anonymity and tie rule are set once here and
/// can't change mid-season.
struct NewGameView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @AppStorage(ManagerSettings.nameKey) private var managerName = ""

    @State private var name = ""
    @State private var season = LeagueConfig.shared.season
    @State private var allowRepeats = LeagueConfig.shared.allowRepeatDefault
    @State private var tieRule: TieRule = LeagueConfig.shared.defaultTieRule
    @State private var anonymity: AnonymityMode = .named

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Game") {
                    TextField("Game name", text: $name)
                    LabeledContent("Season", value: season)
                }

                Section("Rules") {
                    Toggle("Allow team repeats", isOn: $allowRepeats)

                    Picker("Tie / all-eliminated", selection: $tieRule) {
                        ForEach(TieRule.allCases) { Text($0.label).tag($0) }
                    }
                    Text(tieRule.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Summaries") {
                    Picker("Anonymity", selection: $anonymity) {
                        ForEach(AnonymityMode.allCases) { Text($0.label).tag($0) }
                    }
                }
            }
            .navigationTitle("New Game")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { create() }
                        .disabled(trimmedName.isEmpty)
                }
            }
        }
    }

    private func create() {
        let game = Game(
            name: trimmedName,
            season: season,
            allowRepeats: allowRepeats,
            tieRule: tieRule,
            anonymityMode: anonymity
        )
        context.insert(game)

        // The manager always plays in games they create (spec §13b.2 ⚑).
        let manager = managerName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !manager.isEmpty {
            let player = Player(name: manager, game: game, isManager: true)
            context.insert(player)
            game.players.append(player)
        }
        dismiss()
    }
}
