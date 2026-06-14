import Foundation
#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif

/// Starts the Google Mobile Ads SDK once at launch (no-op until the package is
/// linked). Requires `GADApplicationIdentifier` (the AdMob App ID) in Info.plist.
enum AdsBootstrap {
    static func start() {
        #if canImport(GoogleMobileAds)
        MobileAds.shared.start(completionHandler: nil)
        #endif
    }
}
