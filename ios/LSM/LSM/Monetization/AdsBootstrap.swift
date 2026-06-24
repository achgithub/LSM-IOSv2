import Foundation

/// Bootstraps ads at launch: gathers GDPR/UMP consent and App Tracking
/// Transparency authorization *before* starting the Google Mobile Ads SDK (see
/// `AdConsent`). No-op until the package is linked. Requires
/// `GADApplicationIdentifier` (the AdMob App ID) and, for ATT, an
/// `NSUserTrackingUsageDescription` in Info.plist.
@MainActor
enum AdsBootstrap {
    static func start() {
        AdConsent.gatherThenStart()
    }
}
