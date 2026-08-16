import SwiftUI
import SwiftData
import Observation

/// Shared state/logic for "list this manager's cloud games, pull one at a
/// time" — used by `GameSyncPickerView` (the post-link-device picker) and
/// inlined into `ProfileSettingsView`/`ProfileSettingsViewV2` (the
/// "come back later for another game" case from ordinary Settings). One
/// model, two presentations, so the local-existence check and the ad gate
/// on `sync` only exist in one place.
@MainActor
@Observable
final class GameSyncListModel {
    var games: [RemoteGameSummary] = []
    var isLoading = true
    var loadError: String?
    var syncingTokens: Set<String> = []
    var syncedTokens: Set<String> = []
    var errorsByToken: [String: String] = [:]

    /// `Game.cloudGameTokenRaw` values already present on this device,
    /// refreshed on every `load()` — a game whose token is in this set is
    /// already local, so its row shows status rather than a Sync button.
    private(set) var localTokens: Set<String> = []

    func isLocal(_ game: RemoteGameSummary) -> Bool {
        localTokens.contains(game.gameToken.lowercased()) || syncedTokens.contains(game.gameToken)
    }

    func load(context: ModelContext) async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        let existing = (try? context.fetch(FetchDescriptor<Game>())) ?? []
        localTokens = Set(existing.compactMap { $0.cloudGameTokenRaw?.lowercased() })
        do {
            games = try await GameSyncClient.shared.listGames()
        } catch {
            loadError = error.localizedDescription
        }
    }

    /// Free-tier users watch a rewarded ad first (see `AdGate`); subscribers
    /// (No Ads and above) sync immediately. Never hard-blocked on ad fill.
    func sync(_ game: RemoteGameSummary, context: ModelContext) {
        AdGate.run { [weak self] in
            Task { await self?.performSync(game, context: context) }
        }
    }

    private func performSync(_ game: RemoteGameSummary, context: ModelContext) async {
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
