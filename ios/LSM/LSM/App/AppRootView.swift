import SwiftUI

/// App entry view: shows the animated brand splash once over the main UI, then
/// hands off at the frozen 2.5s mark. The tab view loads underneath during the
/// splash so its startup work (ads, purchases) is already running on handoff.
struct AppRootView: View {
    @State private var showSplash = true
    /// Drives in-app language: changing it re-keys the tree (so every view
    /// re-reads its localized strings) and updates `\.locale` for date/number
    /// and plural formatting.
    @State private var localization = LocalizationManager.shared
    /// Held here (above the language `.id` re-key below) so the chosen tab is
    /// preserved when changing language recreates the tab view — otherwise it'd
    /// reset to Games. Stays on Settings while you switch languages.
    @State private var selectedTab: RootTab = .games
    @StateObject private var maintenance = MaintenanceState.shared

    var body: some View {
        ZStack(alignment: .top) {
            RootTabView(splashActive: showSplash, selection: $selectedTab)
                .environment(EnabledLeagues.shared)

            if showSplash {
                SplashView {
                    withAnimation(.easeOut(duration: 0.35)) { showSplash = false }
                }
                .transition(.opacity)
                .zIndex(1)
            }

            if maintenance.isActive && !showSplash {
                MaintenanceBanner(message: maintenance.message)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(2)
            }
        }
        .animation(.easeInOut, value: maintenance.isActive)
        .environment(localization)
        .environment(\.locale, localization.locale)
        .id(localization.language)
    }
}

/// Global "the backend is in maintenance mode" banner — set by MaintenanceState
/// whenever any cloud call (sports data, backup, publish, manager, submissions,
/// attest) detects the shared 503 maintenance shape. Sits above every tab so it
/// covers reads served from cache as well as write-path failures.
private struct MaintenanceBanner: View {
    let message: String?

    var body: some View {
        Text(message ?? "We're doing scheduled maintenance — back shortly.")
            .font(.footnote.weight(.medium))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(.orange, in: Rectangle())
            .foregroundStyle(.black)
    }
}
