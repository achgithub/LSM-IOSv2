import SwiftUI

/// The five tabs. Tagged so the selection survives the language re-key (see
/// `AppRootView`): changing language recreates this view, so the selection lives
/// in the parent and is restored via the binding rather than resetting to Games.
enum RootTab: Hashable { case games, players, matches, standings, settings }

/// The five-tab navigation: Games, Players, Matches, Standings, Settings.
/// (Picks are entered inside a game — Games → Enter Picks — so the second tab
/// is the reusable player roster rather than a read-only picks view.)
struct RootTabView: View {
    /// True while the launch splash is still showing — modal presentations
    /// (onboarding, the league downgrade block) wait until it's gone so they
    /// don't pop over the splash (a `.sheet`/`.fullScreenCover` presents at
    /// the window level).
    var splashActive: Bool = false
    /// Owned by `AppRootView` so it persists across the language re-key.
    @Binding var selection: RootTab
    @AppStorage(ManagerSettings.nameKey) private var managerName = ""
    @State private var entitlements = Entitlements.shared
    @State private var lockoutState = DeviceLockoutState.shared
    @State private var submissionBadgeStore = SubmissionBadgeStore.shared
    @State private var syncCoordinator = SyncCoordinator.shared
    @Environment(EnabledLeagues.self) private var enabled
    @Environment(\.modelContext) private var context
    @State private var showLeagueManager = false
    // @Environment(\.scenePhase) private var scenePhase  // interstitial dropped 2026-06-15

    private var graceDaysRemaining: Int? { enabled.graceDaysRemaining(entitlements) }

    var body: some View {
        VStack(spacing: 0) {
            if let days = graceDaysRemaining {
                Button {
                    showLeagueManager = true
                } label: {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text(days == 1
                             ? AppString("1 day left to fit your plan's leagues")
                             : AppString("\(days) days left to fit your plan's leagues"))
                            .font(.footnote.weight(.semibold))
                        Spacer()
                        Image(systemName: "chevron.right").font(.footnote)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.orange.opacity(0.16))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.orange)
            }
            TabView(selection: $selection) {
                GamesListView()
                    .tabItem { Label("Games", systemImage: "trophy") }
                    .tag(RootTab.games)
                PlayersView()
                    .tabItem { Label("Players", systemImage: "person.2") }
                    .tag(RootTab.players)
                MatchesView()
                    .tabItem { Label("Matches", systemImage: "sportscourt") }
                    .tag(RootTab.matches)
                StandingsView()
                    .tabItem { Label("Standings", systemImage: "list.number") }
                    .tag(RootTab.standings)
                SettingsView()
                    .tabItem { Label("Settings", systemImage: "gearshape") }
                    .tag(RootTab.settings)
            }
            // App-wide banner at the very bottom; only for ad-supported tiers.
            // Kept OUTSIDE the TabView (not a safeAreaInset on it) so it renders
            // reliably and never overlaps the tab bar's touch area.
            if entitlements.shouldShowAds {
                AdBannerView()
            }
        }
        .environment(entitlements)
        .environment(submissionBadgeStore)
        .environment(syncCoordinator)
        .sheet(isPresented: .constant(!splashActive && managerName.isEmpty)) {
            ManagerOnboardingView(managerName: $managerName)
        }
        // ReauthorizeDeviceView asks for the email itself when linkedEmail
        // isn't cached locally (the server-side account link can exist even
        // when this device never recorded that success — see its header
        // comment), so this doesn't need to gate on linkedEmail being set.
        .sheet(isPresented: Binding(
            get: { !splashActive && !managerName.isEmpty && lockoutState.isLockedOut },
            set: { if !$0 { lockoutState.clear() } }
        )) {
            ReauthorizeDeviceView()
        }
        .sheet(isPresented: $showLeagueManager) {
            LeagueDowngradeView(forced: false).environment(entitlements)
        }
        // Forced only once the 14-day grace period has fully elapsed while
        // still over allowance — during the grace period the banner above
        // is the only nudge, nothing is blocked (see EnabledLeagues.mustBlock).
        .fullScreenCover(isPresented: .constant(!splashActive && enabled.mustBlock(entitlements))) {
            LeagueDowngradeView(forced: true).environment(entitlements)
        }
        .task {
            await AppBootstrap.run(context: context, entitlements: entitlements, enabled: enabled, syncCoordinator: syncCoordinator)
        }
        // Interstitial dropped (2026-06-15) — foreground trigger disabled.
        // .onChange(of: scenePhase) { _, phase in
        //     if phase == .active { InterstitialAdManager.shared.showIfDue() }
        // }
    }
}
