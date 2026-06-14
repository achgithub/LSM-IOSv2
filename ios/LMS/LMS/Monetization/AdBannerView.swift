import SwiftUI
#if canImport(GoogleMobileAds)
import GoogleMobileAds
import UIKit
#endif

/// An AdMob banner. Renders the real banner when the Google Mobile Ads SDK is
/// linked; otherwise a labelled placeholder so the ad slot is visible during
/// development. Callers should only show this when `Entitlements.shouldShowAds`.
struct AdBannerView: View {
    var body: some View {
        #if canImport(GoogleMobileAds)
        BannerContainer().frame(height: 50)
        #else
        Text("Ad")
            .font(.caption2).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity).frame(height: 50)
            .background(Color.secondary.opacity(0.12))
        #endif
    }
}

#if canImport(GoogleMobileAds)
private struct BannerContainer: UIViewRepresentable {
    func makeUIView(context: Context) -> BannerView {
        let banner = BannerView(adSize: AdSizeBanner)
        banner.adUnitID = AdUnitIDs.banner
        banner.rootViewController = AdRootViewController.current
        banner.load(Request())
        return banner
    }

    func updateUIView(_ uiView: BannerView, context: Context) {}
}

/// The key window's root view controller, for presenting/anchoring ads.
enum AdRootViewController {
    static var current: UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .rootViewController
    }
}
#endif
