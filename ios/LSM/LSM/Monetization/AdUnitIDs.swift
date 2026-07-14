import Foundation

/// AdMob unit IDs. The App ID also goes in Info.plist as `GADApplicationIdentifier`
/// (real always — only the ad UNIT ids switch for test ads, never the App ID).
///
/// Was `true` while the app was TestFlight-only: AdMob can't review an app
/// with no App Store URL yet, so the real ad units served no fill at all
/// pre-review, and Google's own guidance for that situation is to use their
/// demo ad unit IDs (`Demo` below) rather than real ones. Flipped to `false`
/// for App Store submission — real ad units now serve live inventory.
enum AdUnitIDs {
    static let useTestAds = false

    static let appID = "ca-app-pub-3510617456822042~1632957503"

    /// Real production ad unit IDs — untouched, kept for when `useTestAds` flips.
    private enum Live {
        static let banner = "ca-app-pub-3510617456822042/4127258904"
        static let interstitial = "ca-app-pub-3510617456822042/6174837744"
        static let rewarded = "ca-app-pub-3510617456822042/7400289502"
    }

    /// Google's official demo ad unit IDs — always serve a test creative,
    /// regardless of app review/account status. See developers.google.com/admob/ios/test-ads.
    private enum Demo {
        static let banner = "ca-app-pub-3940256099942544/2435281174"
        static let interstitial = "ca-app-pub-3940256099942544/4411468910"
        static let rewarded = "ca-app-pub-3940256099942544/1712485313"
    }

    static var banner: String { useTestAds ? Demo.banner : Live.banner }
    static var interstitial: String { useTestAds ? Demo.interstitial : Live.interstitial }
    static var rewarded: String { useTestAds ? Demo.rewarded : Live.rewarded }
}
