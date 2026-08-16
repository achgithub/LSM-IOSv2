import SwiftUI
import SwiftData

/// Card/List restyle of `GameSyncPickerView` — same logic (list cloud games,
/// pull one at a time, never bulk — see `GameSyncBuilder`'s header comment).
/// Reachable both from onboarding right after linking a device, and later
/// from V2 Settings for a device that just wants an additional game.
struct GameSyncPickerViewV2: View {
    @Environment(\.modelContext) private var context

    /// Called once, when the user taps Done — lets a presenting onboarding
    /// flow move on regardless of whether anything was actually synced.
    var onFinished: (() -> Void)?

    @State private var games: [RemoteGameSummary] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var syncingTokens: Set<String> = []
    @State private var syncedTokens: Set<String> = []
    @State private var errorsByToken: [String: String] = [:]

    var body: some View {
        List {
            if let loadError {
                Section {
                    Text(loadError).foregroundStyle(V2Theme.textSecondary)
                    Button("Try Again") { Task { await load() } }
                        .foregroundStyle(V2Theme.accent)
                }
            } else if isLoading {
                Section { ProgressView() }
            } else if games.isEmpty {
                Section {
                    Text("No cloud games found for this account.")
                        .foregroundStyle(V2Theme.textSecondary)
                }
            } else {
                Section {
                    ForEach(games) { game in
                        gameRow(game)
                    }
                } footer: {
                    Text("Pick a game to bring it to this device. You can come back later for the rest.")
                }
            }
        }
        .v2Header("Sync Games")
        .task { await load() }
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
                        .foregroundStyle(V2Theme.textPrimary)
                    Text("\(game.mode.capitalized) · Round \(game.roundNumber)")
                        .font(.footnote)
                        .foregroundStyle(V2Theme.textSecondary)
                }
                Spacer()
                trailingControl(for: game)
            }
            if let message = errorsByToken[game.gameToken] {
                Text(message).font(.caption).foregroundStyle(V2Theme.danger)
            }
        }
    }

    @ViewBuilder
    private func trailingControl(for game: RemoteGameSummary) -> some View {
        if syncedTokens.contains(game.gameToken) {
            Label("Synced", systemImage: "checkmark.circle.fill")
                .labelStyle(.iconOnly)
                .foregroundStyle(V2Theme.accent)
        } else if syncingTokens.contains(game.gameToken) {
            ProgressView()
        } else {
            Button("Sync") { Task { await sync(game) } }
                .buttonStyle(.bordered)
                .tint(V2Theme.accent)
        }
    }

    private func load() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            games = try await GameSyncClient.shared.listGames()
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func sync(_ game: RemoteGameSummary) async {
        syncingTokens.insert(game.gameToken)
        errorsByToken[game.gameToken] = nil
        defer { syncingTokens.remove(game.gameToken) }
        do {
            let bundle = try await GameSyncClient.shared.pullGame(gameToken: game.gameToken)
            try GameSyncBuilder.build(from: bundle, gameToken: game.gameToken, into: context)
            syncedTokens.insert(game.gameToken)
        } catch {
            errorsByToken[game.gameToken] = error.localizedDescription
        }
    }
}
