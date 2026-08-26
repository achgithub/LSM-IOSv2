import SwiftUI

/// V2's root shell — the real app entry point when `V2PreviewFlag` is on,
/// alongside `RootTabView` (v1). Mirrors `RootTabView`'s non-navigation
/// responsibilities (grace-period banner, onboarding/reauth sheets, forced
/// league-downgrade cover, ad banner, environment injection) so V2 stops
/// depending on being nested inside v1's hierarchy to get any of that for
/// free — see `docs/v1-to-v2-cutover-plan.md` §3 (branch
/// `worktree-agent-a112bd9b78b63937e`) for the plan this implements.
/// Startup bootstrap itself (ads/purchases/entitlements/etc.) is shared via
/// `AppBootstrap`, not duplicated, since that's the monetization-critical
/// part neither root can afford to drift on.
struct V2RootView: View {
    var splashActive: Bool = false
    @AppStorage(ManagerSettings.nameKey) private var managerName = ""
    @State private var entitlements = Entitlements.shared
    @State private var lockoutState = DeviceLockoutState.shared
    @State private var submissionBadgeStore = SubmissionBadgeStore.shared
    @State private var pushCoordinator = PushCoordinator.shared
    @Environment(EnabledLeagues.self) private var enabled
    @Environment(\.modelContext) private var context
    @State private var showLeagueManager = false

    private var graceDaysRemaining: Int? { enabled.graceDaysRemaining(entitlements) }

    var body: some View {
        v2Content
            .environment(entitlements)
            .environment(submissionBadgeStore)
            .environment(pushCoordinator)
            .sheet(isPresented: .constant(!splashActive && managerName.isEmpty)) {
                ManagerOnboardingView(managerName: $managerName)
            }
            .sheet(isPresented: Binding(
                get: { !splashActive && !managerName.isEmpty && lockoutState.isLockedOut },
                set: { if !$0 { lockoutState.clear() } }
            )) {
                ReauthorizeDeviceView()
            }
            .sheet(isPresented: $showLeagueManager) {
                LeagueDowngradeView(forced: false).environment(entitlements)
            }
            .fullScreenCover(isPresented: .constant(!splashActive && enabled.mustBlock(entitlements))) {
                LeagueDowngradeView(forced: true).environment(entitlements)
            }
            .task {
                await AppBootstrap.run(context: context, entitlements: entitlements, enabled: enabled, pushCoordinator: pushCoordinator)
            }
    }

    private var v2Content: some View {
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
            NavigationStack {
                V2PreviewMenuView()
            }
            // Without this, the NavigationStack settles at its content's
            // ideal height instead of claiming the VStack's remaining
            // space, leaving a blank gap between it and the ad banner below
            // — the stadium background lives inside the pushed screen (see
            // `V2StadiumBackdrop`'s doc comment), so a short NavigationStack
            // means a short background too, cut off well above the banner.
            .frame(maxHeight: .infinity)
            // Matches RootTabView: outside the nav stack, not a safeAreaInset
            // on it, for the same reliability reason (see RootTabView).
            if entitlements.shouldShowAds {
                // A stark white ad footer butted straight against themed
                // photo content read as an interruption rather than a
                // deliberate end to the scene. A thin solid strip closes
                // the theme off on purpose instead.
                Rectangle()
                    .fill(V2Theme.background)
                    .frame(height: 3)
                AdBannerView()
            }
        }
    }
}
