import Combine
import SwiftUI

/// Shared chrome for the three results-entry screens (`ResultsEntryViewV2`,
/// `PredictorResultsEntryViewV2`, `KillerResultsEntryViewV2`): the loading
/// overlay, the floating header (title + live-refresh button + Done), the
/// per-second timer that keeps the throttle countdown live, and the two
/// startup tasks (fixture load, throttle rearm). Only this identical
/// wrapper is factored out — each screen's own close-round logic differs
/// too much to unify safely and stays where it is (LMS's tie/winner
/// detection, Predictor's joker + suppressible warning sheet, Killer's
/// split-outcome + incomplete-players + double-tap guard — see V2 audit
/// 3.2). The bottom safe-area bar (each screen's own `bottomBar`, with its
/// own alerts/confirmation dialogs attached) and LMS's top safe-area
/// tutorial banner — which Predictor/Killer's results screens don't carry
/// — stay with each caller, applied after this modifier.
private struct V2ResultsEntryChromeModifier: ViewModifier {
    let title: String
    let tint: Color
    let isLoading: Bool
    let leagues: [LeagueOption]
    let refresh: LiveMatchRefreshState
    let onPullFromServer: @MainActor () async -> Void
    let onLoad: @MainActor () async -> Void
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content
            .v2LoadingOverlay(isLoading, label: "Loading fixtures…")
            .v2FloatingHeader(title, showBack: false) {
                HStack(spacing: 14) {
                    LiveMatchRefreshButton(state: refresh) { await onPullFromServer() }
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundStyle(tint)
                }
            }
            .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { tick in
                if refresh.isThrottled { refresh.now = tick }
            }
            .task { await onLoad() }
            .task { refresh.rearm(for: leagues) }
    }
}

extension View {
    /// `title` should already include "Results · Round N"; `refresh` is the
    /// screen's own `@State private var refresh = LiveMatchRefreshState()`
    /// (a reference type, so this modifier mutating it is visible back to
    /// the caller without a binding).
    func v2ResultsEntryChrome(
        title: String,
        tint: Color,
        isLoading: Bool,
        leagues: [LeagueOption],
        refresh: LiveMatchRefreshState,
        onPullFromServer: @escaping @MainActor () async -> Void,
        onLoad: @escaping @MainActor () async -> Void
    ) -> some View {
        modifier(V2ResultsEntryChromeModifier(
            title: title, tint: tint, isLoading: isLoading, leagues: leagues,
            refresh: refresh, onPullFromServer: onPullFromServer, onLoad: onLoad
        ))
    }
}
