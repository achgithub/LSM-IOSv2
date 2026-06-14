import Foundation
#if canImport(RevenueCat)
import RevenueCat
#endif

/// RevenueCat wrapper. Compiles with or without the SDK present (guarded by
/// `canImport`), so the build stays green until the `purchases-ios` package is
/// added in Xcode. Until a real API key is set, the app runs on the dev tier
/// override (Settings) — exactly the with/without-ads testing flow.
@MainActor
final class PurchaseService {
    static let shared = PurchaseService()

    // TODO: real key from RevenueCat → Project → API Keys → public app-specific.
    private static let apiKey = "appl_REPLACE_ME"

    private(set) var isConfigured = false

    private init() {}

    /// Call once at launch. No-ops if the SDK isn't linked or the key is unset.
    func configure() {
        #if canImport(RevenueCat)
        guard !isConfigured, !Self.apiKey.contains("REPLACE_ME") else { return }
        Purchases.logLevel = .debug
        Purchases.configure(withAPIKey: Self.apiKey)
        isConfigured = true
        Task { await refreshTier() }
        #endif
    }

    func refreshTier() async {
        #if canImport(RevenueCat)
        guard isConfigured else { return }
        do {
            let info = try await Purchases.shared.customerInfo()
            Entitlements.shared.apply(tier: Self.tier(from: info))
        } catch {
            // Leave the current tier; a later refresh (foreground) can retry.
        }
        #endif
    }

    func restore() async {
        #if canImport(RevenueCat)
        guard isConfigured else { return }
        do {
            let info = try await Purchases.shared.restorePurchases()
            Entitlements.shared.apply(tier: Self.tier(from: info))
        } catch {
            // Surface to the user in a later pass; no-op for now.
        }
        #endif
    }

    #if canImport(RevenueCat)
    private static func tier(from info: CustomerInfo) -> Tier {
        if info.entitlements[Entitlements.entitlementPro]?.isActive == true { return .pro }
        if info.entitlements[Entitlements.entitlementNoAds]?.isActive == true { return .noAds }
        return .free
    }
    #endif
}
