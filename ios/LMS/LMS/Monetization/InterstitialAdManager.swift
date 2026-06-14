import Foundation
#if canImport(GoogleMobileAds)
import GoogleMobileAds
import UIKit
#endif

/// Timed interstitial, shown on returning to the foreground once enough active
/// time has passed (mirrors the darts 15-minute timer interstitial). Compiles
/// without the SDK linked (then a no-op). Targets Google Mobile Ads v11+.
@MainActor
final class InterstitialAdManager: NSObject {
    static let shared = InterstitialAdManager()

    /// Minimum gap between timed interstitials.
    private static let minInterval: TimeInterval = 15 * 60

    // Seed to "now" so we never interrupt a cold launch — the first timed
    // interstitial can only fire after `minInterval` of use.
    private var lastShown = Date()

    #if canImport(GoogleMobileAds)
    private var ad: InterstitialAd?
    private var loading = false
    #endif

    func preload() {
        #if canImport(GoogleMobileAds)
        guard ad == nil, !loading else { return }
        loading = true
        InterstitialAd.load(with: AdUnitIDs.interstitial, request: Request()) { [weak self] loaded, _ in
            guard let self else { return }
            self.loading = false
            self.ad = loaded
            self.ad?.fullScreenContentDelegate = self
        }
        #endif
    }

    /// Call when the app returns to the foreground. Shows the interstitial only
    /// if ads are enabled, the interval has elapsed, and nothing else is on screen.
    func showIfDue() {
        guard Entitlements.shared.shouldShowAds else { return }
        guard Date().timeIntervalSince(lastShown) >= Self.minInterval else { return }
        #if canImport(GoogleMobileAds)
        guard let ad, let root = AdRootViewController.current, AdLock.acquire() else { return }
        lastShown = Date()
        ad.present(from: root)
        #endif
    }
}

#if canImport(GoogleMobileAds)
extension InterstitialAdManager: FullScreenContentDelegate {
    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) { reset() }
    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) { reset() }

    private func reset() {
        AdLock.release()
        ad = nil
        preload()
    }
}
#endif
