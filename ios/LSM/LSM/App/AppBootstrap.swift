import Foundation
import SwiftData

/// Startup work shared by whichever root shell is active (`RootTabView` for
/// v1, `V2RootView` for V2) — extracted so the two roots can't drift on
/// this, since it's the monetization/entitlements-critical part: ads,
/// purchases, entitlements refresh, grace-period clock, league pruning,
/// first-launch data fill, registry refresh, and outbox retry. Everything
/// UI-specific (onboarding sheet, ad banner placement, grace banner) stays
/// in each root, since that's exactly where the two are allowed to differ.
enum AppBootstrap {
    @MainActor
    static func run(context: ModelContext, entitlements: Entitlements, enabled: EnabledLeagues, syncCoordinator: SyncCoordinator) async {
        #if DEBUG
        DemoRosterSeeder.seedIfNeeded(context: context)
        DemoPredictorSeeder.seedIfNeeded(context: context)
        await UITestPWAScenarioSeeder.seedIfRequested(context: context, entitlements: entitlements)
        #endif
        PurchaseService.shared.configure()
        // Skip ad bootstrap under UI tests so the ATT / UMP consent dialogs
        // never appear and make the launch flow flaky.
        if !ProcessInfo.processInfo.arguments.contains("-uitests") {
            AdsBootstrap.start()
            RewardedAdManager.shared.preload()
        }
        await entitlements.refresh()
        // Starts (or clears) the 14-day grace clock — anchored to this
        // launch actually happening, never a background timestamp, so
        // the clock can't expire unseen while the manager is away (see
        // EnabledLeagues.updateGracePeriod's doc comment).
        enabled.updateGracePeriod(entitlements)
        // Drop any leagues that no longer exist. Going over the subscription
        // allowance (e.g. a lapsed sub) is never force-corrected immediately —
        // existing games keep running for the full grace period; only
        // starting a NEW game in a not-yet-active league is gated right away
        // (see NewGameView).
        EnabledLeagues.shared.pruneInvalid()
        // The device's one-ever free look at real data (home league only) —
        // see LeagueData's doc comment. A no-op after the first-ever launch.
        await LeagueData.performFirstLaunchFreeFillIfNeeded()
        // Fire-and-forget: refreshes the league list for the *next* launch
        // (see Leagues.refreshFromRegistry) — never blocks this launch.
        Task { await Leagues.refreshFromRegistry() }
        // One-time-ever: flags existing cloud games so the outbox retry
        // right below picks them up and backfills game_config_json for
        // per-game sync. See `SyncCoordinator.backfillGameConfigIfNeeded`.
        syncCoordinator.backfillGameConfigIfNeeded(context: context)
        // Fire-and-forget: clears the client-side outbox — any push from
        // a previous session that never confirmed (dropped connection,
        // backgrounded mid-request) gets retried now rather than waiting
        // for the manager to notice and tap Sync. See
        // `SyncCoordinator.retryOutstanding`/`Game.pushPending`.
        Task { await syncCoordinator.retryOutstanding(context: context) }
    }
}
