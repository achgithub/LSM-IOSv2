import Foundation
#if canImport(GoogleMobileAds)
import GoogleMobileAds
import UIKit
#endif

/// Single app-wide rewarded ad (mirrors the darts rewardedManager). Compiles
/// without the SDK linked — `show` then simply reports "not earned". Targets the
/// Google Mobile Ads SDK v11+ API (no `GAD` prefix).
@MainActor
final class RewardedAdManager: NSObject {
    static let shared = RewardedAdManager()

    #if canImport(GoogleMobileAds)
    private var ad: RewardedAd?
    private var loading = false
    private var completion: ((Bool) -> Void)?
    private var earned = false
    #endif

    func preload() {
        #if canImport(GoogleMobileAds)
        guard ad == nil, !loading else { return }
        loading = true
        RewardedAd.load(with: AdUnitIDs.rewarded, request: Request()) { [weak self] loaded, _ in
            guard let self else { return }
            self.loading = false
            self.ad = loaded
            self.ad?.fullScreenContentDelegate = self
        }
        #endif
    }

    var isReady: Bool {
        #if canImport(GoogleMobileAds)
        return ad != nil
        #else
        return false
        #endif
    }

    /// Presents the rewarded ad; `completion(true)` if the reward was earned.
    /// Reports false immediately if not ready or another fullscreen ad is showing.
    func show(completion: @escaping (Bool) -> Void) {
        #if canImport(GoogleMobileAds)
        guard let ad, let root = AdRootViewController.current, AdLock.acquire() else {
            completion(false)
            return
        }
        self.completion = completion
        self.earned = false
        ad.present(from: root) { [weak self] in
            self?.earned = true
        }
        #else
        completion(false)
        #endif
    }
}

#if canImport(GoogleMobileAds)
extension RewardedAdManager: FullScreenContentDelegate {
    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) { finish() }

    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) { finish() }

    private func finish() {
        AdLock.release()
        let done = completion
        let earnedNow = earned
        completion = nil
        ad = nil
        preload() // reload for next time
        done?(earnedNow)
    }
}
#endif
