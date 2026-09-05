import SwiftUI
import SwiftData

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
    @AppStorage(AccountSettings.linkedEmailKey) private var linkedEmail = ""
    @State private var entitlements = Entitlements.shared
    @State private var lockoutState = DeviceLockoutState.shared
    @State private var recoveryPrompt = RecoveryEmailPrompt.shared
    @State private var submissionBadgeStore = SubmissionBadgeStore.shared
    @State private var pushCoordinator = PushCoordinator.shared
    @Environment(EnabledLeagues.self) private var enabled
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @State private var showLeagueManager = false
    @Query(sort: \Game.createdAt, order: .reverse) private var games: [Game]

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
            // Guarded against every other sheet/cover this root can raise —
            // an optional nudge must never be the thing that stops onboarding,
            // a device reauth, or a forced downgrade from being dealt with.
            // `evaluate` only flips this on when it's genuinely due, so the
            // binding is a presentation guard, not the decision.
            .sheet(isPresented: Binding(
                get: {
                    !splashActive && !managerName.isEmpty && !lockoutState.isLockedOut
                        && !enabled.mustBlock(entitlements) && recoveryPrompt.isPresented
                },
                set: { if !$0 { recoveryPrompt.isPresented = false } }
            )) {
                RecoveryEmailPromptView()
            }
            .fullScreenCover(isPresented: .constant(!splashActive && enabled.mustBlock(entitlements))) {
                LeagueDowngradeView(forced: true).environment(entitlements)
            }
            .task {
                await AppBootstrap.run(context: context, entitlements: entitlements, enabled: enabled, pushCoordinator: pushCoordinator)
                // After bootstrap, not before — the tier has to be resolved
                // for `evaluate` to tell a cloud manager from a Free one.
                recoveryPrompt.evaluate(entitlements: entitlements, linkedEmail: linkedEmail)
            }
            // V2-only auto-refresh foreground trigger — see
            // docs/sync-refresh-policy.md. RootTabView (v1) intentionally
            // doesn't get this; v1 keeps today's manual, AdGate-only
            // refresh. `SyncScheduler.refreshIfDue` no-ops for Free itself,
            // so no extra gating needed here.
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task {
                    await SyncScheduler.shared.refreshIfDue(games: games, leagues: enabled.leagues, entitlements: entitlements)
                }
                // Re-checked on every foreground, not just at launch: an
                // upgrade bought mid-session (or a tier that resolved late
                // after an offline launch) has to be able to raise the nudge
                // without waiting for a cold start. `evaluate` no-ops when
                // it isn't due.
                recoveryPrompt.evaluate(entitlements: entitlements, linkedEmail: linkedEmail)
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
