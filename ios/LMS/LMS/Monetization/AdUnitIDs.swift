import Foundation

/// AdMob unit IDs. These are Google's official **test** IDs (iOS) — safe to use
/// during development; serving them in production is an AdMob policy violation,
/// so swap in real IDs from the AdMob console before release (same note as the
/// darts ads.ts). The App ID also goes in Info.plist as `GADApplicationIdentifier`.
enum AdUnitIDs {
    static let appID = "ca-app-pub-3940256099942544~1458002511"
    static let banner = "ca-app-pub-3940256099942544/2934735716"
    static let interstitial = "ca-app-pub-3940256099942544/4411468910"
    static let rewarded = "ca-app-pub-3940256099942544/1712485313"
}
