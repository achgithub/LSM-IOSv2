import SwiftUI

/// The five-tab navigation: Games, Players, Scores, Standings, Settings.
/// (Picks are entered inside a game — Games → Enter Picks — so the second tab
/// is the reusable player roster rather than a read-only picks view.)
struct RootTabView: View {
    @AppStorage(ManagerSettings.nameKey) private var managerName = ""
    @State private var entitlements = Entitlements.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            GamesListView()
                .tabItem { Label("Games", systemImage: "trophy") }
            PlayersView()
                .tabItem { Label("Players", systemImage: "person.2") }
            ScoresView()
                .tabItem { Label("Scores", systemImage: "sportscourt") }
            StandingsView()
                .tabItem { Label("Standings", systemImage: "list.number") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        // App-wide banner pinned above the tab bar; only for ad-supported tiers.
        .safeAreaInset(edge: .bottom) {
            if entitlements.shouldShowAds {
                AdBannerView()
            }
        }
        .environment(entitlements)
        .sheet(isPresented: .constant(managerName.isEmpty)) {
            ManagerOnboardingView(managerName: $managerName)
        }
        .task {
            PurchaseService.shared.configure()
            AdsBootstrap.start()
            InterstitialAdManager.shared.preload()
            RewardedAdManager.shared.preload()
            await entitlements.refresh()
        }
        .onChange(of: scenePhase) { _, phase in
            // Timed interstitial on returning to the foreground.
            if phase == .active { InterstitialAdManager.shared.showIfDue() }
        }
    }
}
