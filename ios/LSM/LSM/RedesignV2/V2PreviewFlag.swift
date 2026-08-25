import Foundation

/// Shared `@AppStorage` key selecting the app's root shell — `AppRootView`
/// shows `V2RootView` when true (the default for anyone who's never
/// touched it), `RootTabView` (v1) when false. Toggled from either root's
/// own Settings screen (`SettingsView`/`SettingsViewV2`) — flipping it
/// switches the live root immediately, no relaunch needed. Works in all
/// builds (not `#if DEBUG`-gated) so v1 stays reachable as a real fallback
/// over TestFlight/App Store, not just in the simulator.
enum V2PreviewFlag {
    static let key = "v2PreviewEnabled"
}
