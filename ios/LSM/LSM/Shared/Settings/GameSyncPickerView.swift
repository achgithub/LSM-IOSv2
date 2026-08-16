import SwiftUI
import SwiftData

/// Lists this manager's cloud games and lets the user pull individual ones
/// down to this device — one at a time, by explicit choice, never all at
/// once (see `GameSyncBuilder`'s header comment on why "sync a game" is
/// deliberately not a bulk restore). Reachable from onboarding right after
/// linking a device — the only other entry point, "come back later for
/// another game," is now inlined into `ProfileSettingsView` instead of a
/// separate screen. State/logic lives in `GameSyncListModel`, shared with
/// that inline copy so there's one local-existence check and one ad gate.
struct GameSyncPickerView: View {
    @Environment(\.modelContext) private var context
    @State private var model = GameSyncListModel()

    /// Called once, when the user taps Done — lets a presenting onboarding
    /// flow move on regardless of whether anything was actually synced.
    var onFinished: (() -> Void)?

    var body: some View {
        List {
            if let loadError = model.loadError {
                Section {
                    Text(loadError).foregroundStyle(.secondary)
                    Button("Try Again") { Task { await model.load(context: context) } }
                }
            } else if model.isLoading {
                Section { ProgressView() }
            } else if model.games.isEmpty {
                Section {
                    Text("No cloud games found for this account.")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section {
                    ForEach(model.games) { game in
                        gameRow(game)
                    }
                } footer: {
                    Text("Pick a game to bring it to this device. You can come back later for the rest.")
                }
            }
        }
        .navigationTitle("Sync Games")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load(context: context) }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { onFinished?() }
            }
        }
    }

    @ViewBuilder
    private func gameRow(_ game: RemoteGameSummary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(game.gameName?.isEmpty == false ? game.gameName! : AppString("Untitled Game"))
                        .font(.body)
                    Text("\(game.mode.capitalized) · Round \(game.roundNumber)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                trailingControl(for: game)
            }
            if let message = model.errorsByToken[game.gameToken] {
                Text(message).font(.caption).foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private func trailingControl(for game: RemoteGameSummary) -> some View {
        if model.isLocal(game) {
            Label("On This Device", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        } else if model.syncingTokens.contains(game.gameToken) {
            ProgressView()
        } else {
            Button("Sync") { model.sync(game, context: context) }
                .buttonStyle(.bordered)
        }
    }
}
