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

    private static func startSDK() {
        #if canImport(GoogleMobileAds)
        MobileAds.shared.start(completionHandler: nil)
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
