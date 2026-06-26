import SwiftUI

/// Shared pull-from-server state and throttle for views that import live match
/// data. Wraps the fetch + 120s cooldown that is shared with the Matches tab
/// via `LeagueDataCache.sharedMatchesThrottleUntil`.
///
/// Usage:
///   @State private var refresh = LiveMatchRefreshState()
///   // In toolbar: LiveMatchRefreshButton(state: refresh) { await pullFromServer() }
///   // In timer: if refresh.isThrottled { refresh.now = tick }
@MainActor @Observable final class LiveMatchRefreshState {
    var now: Date = .init()
    var freshUntil: Date?
    var lastPulled: Date?
    var isLoading = false

    var isThrottled: Bool { freshUntil.map { now < $0 } ?? false }

    /// Pull live matches for each league, reload from cache, and rearm the
    /// throttle. Returns the fresh `LeagueData` on success, or `nil` on error.
    func pull(for leagues: [LeagueOption]) async -> LeagueData? {
        isLoading = true
        defer { isLoading = false }
        for league in leagues { _ = try? await LeagueData.pullLiveMatches(for: league) }
        let fresh = try? await LeagueData.load(for: leagues)
        rearm(for: leagues)
        if fresh != nil { lastPulled = Date() }
        return fresh
    }

    /// Resets the throttle clock from the current cache state without fetching.
    /// Call after any load so the button is greyed if the cache is already fresh.
    func rearm(for leagues: [LeagueOption]) {
        now = Date()
        freshUntil = LeagueDataCache.sharedMatchesThrottleUntil(for: leagues.map(\.id))
    }
}

/// Toolbar button that gates the pull action behind AdGate and disables while
/// throttled or loading. Wire up to a `LiveMatchRefreshState`.
struct LiveMatchRefreshButton: View {
    let state: LiveMatchRefreshState
    let action: () async -> Void

    var body: some View {
        Button {
            AdGate.run { Task { await action() } }
        } label: {
            Label("Refresh matches", systemImage: "arrow.down.circle")
        }
        .disabled(state.isLoading || state.isThrottled)
    }
}
