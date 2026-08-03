import Foundation
#if canImport(GoogleMobileAds)
import GoogleMobileAds
import UIKit
#endif
#if canImport(AppTrackingTransparency)
import AppTrackingTransparency
#endif
#if canImport(UserMessagingPlatform)
import UserMessagingPlatform
#endif

/// Gathers ad consent before any ad loads, in Google's recommended order:
/// UMP/GDPR consent form (EEA/UK) → App Tracking Transparency → start the SDK.
/// Each stage degrades to the next when its module isn't linked, so the build
/// stays green with or without the UMP / AppTrackingTransparency frameworks.
@MainActor
enum AdConsent {
    static func gatherThenStart() {
        gatherUMP {
            requestATT {
                startSDK()
            }
        }
    }

    /// GDPR: update consent info, then load + present the consent form if the
    /// user's region requires one. No-op outside the EEA/UK or without UMP linked.
    private static func gatherUMP(_ next: @escaping () -> Void) {
        #if canImport(UserMessagingPlatform)
        UMPConsentInformation.sharedInstance.requestConsentInfoUpdate(with: UMPRequestParameters()) { _ in
            UMPConsentForm.loadAndPresentIfRequired(from: rootViewController()) { _ in
                next()
            }
        }
        #else
        next()
        #endif
    }

    /// iOS App Tracking Transparency. The prompt shows once; if already
    /// determined the callback returns immediately. Denial → non-personalized ads.
    private static func requestATT(_ next: @escaping () -> Void) {
        #if canImport(AppTrackingTransparency)
        ATTrackingManager.requestTrackingAuthorization { _ in
            DispatchQueue.main.async { next() }
        }
        #else
        next()
        #endif
    }

    /// Devices that should always get Google's test ads, even though the app
    /// ships real ad unit IDs everywhere — so a tester's device never serves
    /// (or risks invalid-clicks on) real inventory, without ever needing to
    /// swap IDs before/after release. Find a device's hashed identifier in its
    /// console log (Xcode → Window → Devices and Simulators → view device log,
    /// or Console.app) the first time it requests an ad — Google logs a line
    /// like `To get test ads on this device, set: ...testDeviceIdentifiers =
    /// @[ @"<hash>" ]`. Add that hash here, not the raw IDFA.
    private static let testDeviceIdentifiers: [String] = []

    private static func startSDK() {
        #if canImport(GoogleMobileAds)
        if !testDeviceIdentifiers.isEmpty {
            MobileAds.shared.requestConfiguration.testDeviceIdentifiers = testDeviceIdentifiers
        }
        // `start(completionHandler:)` does real synchronous work on first
        // launch ever (mediation adapter init, disk I/O) — on the calling
        // thread. Called from @MainActor as-is, that's exactly the ~1s+
        // fresh-install hang a tester hit mid-wizard (issue #13). Google's
        // start() is documented safe to call off the main thread, so hop to
        // a background queue for just this call.
        //
        // RootTabView's launch-time `RewardedAdManager.preload()` fires
        // immediately after `AdsBootstrap.start()`, racing this whole
        // UMP → ATT → SDK-init chain — a rewarded ad request made before the
        // SDK has actually started can silently no-fill, and nothing ever
        // retried it (no scenePhase hook, no other preload call site), so
        // `isReady` stayed false for the rest of the session and every
        // "free" refresh fell through to a real, silently-failing network
        // fetch. Re-run preload here once start() genuinely completes.
        DispatchQueue.global(qos: .utility).async {
            MobileAds.shared.start { _ in
                Task { @MainActor in RewardedAdManager.shared.preload() }
            }
        }
        #endif
    }

    #if canImport(UserMessagingPlatform)
    private static func rootViewController() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .rootViewController
    }
    #endif
}
