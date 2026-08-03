import Foundation

/// Shared `@AppStorage` key gating the V2 tab — set from the "Try the new
/// design" toggle in Settings, read in `RootTabView`. Works in all builds
/// (not `#if DEBUG`-gated) so it can be shown to people outside the dev
/// simulator, e.g. over TestFlight.
enum V2PreviewFlag {
    static let key = "v2PreviewEnabled"
}
