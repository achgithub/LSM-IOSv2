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

    /// The result of a restore or purchase, so the UI can always tell the user
    /// what happened (never a silent no-op). `.unavailable` covers the pre-release
    /// state where RevenueCat isn't linked / no key is set yet.
    enum PurchaseOutcome {
        case success(Tier)
        case cancelled
        case failed(String)
        case unavailable
    }

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

    /// Restore previous purchases, reporting the outcome so the UI can confirm
    /// success or surface a failure (no more silent no-op).
    func restore() async -> PurchaseOutcome {
        #if canImport(RevenueCat)
        guard isConfigured else { return .unavailable }
        do {
            let info = try await Purchases.shared.restorePurchases()
            let tier = Self.tier(from: info)
            Entitlements.shared.apply(tier: tier)
            return .success(tier)
        } catch {
            return .failed(error.localizedDescription)
        }
        #else
        return .unavailable
        #endif
    }

    /// Buy the subscription that grants `tier`, reporting the outcome.
    func purchase(_ tier: Tier) async -> PurchaseOutcome {
        #if canImport(RevenueCat)
        guard isConfigured else { return .unavailable }
        do {
            let offerings = try await Purchases.shared.offerings()
            guard let package = Self.package(for: tier, in: offerings) else { return .unavailable }
            let result = try await Purchases.shared.purchase(package: package)
            if result.userCancelled { return .cancelled }
            let newTier = Self.tier(from: result.customerInfo)
            Entitlements.shared.apply(tier: newTier)
            return .success(newTier)
        } catch {
            return .failed(error.localizedDescription)
        }
        #else
        return .unavailable
        #endif
    }

    #if canImport(RevenueCat)
    private static func tier(from info: CustomerInfo) -> Tier {
        if info.entitlements[Entitlements.entitlementPro]?.isActive == true { return .pro }
        if info.entitlements[Entitlements.entitlementNoAds]?.isActive == true { return .noAds }
        return .free
    }

    /// Maps a tier to its RevenueCat package. TODO: confirm the package/product
    /// identifiers in the RevenueCat dashboard. Convention until then: the current
    /// offering exposes a package whose identifier is the tier raw value
    /// ("no_ads" / "pro").
    private static func package(for tier: Tier, in offerings: Offerings) -> Package? {
        let packages = offerings.current?.availablePackages ?? []
        return packages.first { $0.identifier == tier.rawValue }
    }
    #endif
}

extension PurchaseService.PurchaseOutcome {
    /// A user-facing alert for the outcome, or `nil` when nothing should show
    /// (the user cancelled the App Store sheet themselves). `restoring` tailors
    /// the copy for Restore vs. a fresh purchase.
    func alert(restoring: Bool) -> (title: String, message: String)? {
        switch self {
        case .success(let tier):
            if restoring && tier == .free {
                return ("Nothing to restore", "We couldn't find an active subscription on your Apple ID.")
            }
            return (restoring ? "Purchases restored" : "You're subscribed",
                    "Your \(tier.label) plan is now active.")
        case .cancelled:
            return nil
        case .failed(let message):
            return (restoring ? "Restore failed" : "Purchase failed", message)
        case .unavailable:
            return ("Not available yet",
                    "Subscriptions aren't available in this build yet. Please check back after the next update.")
        }
    }
}

/// Identifiable wrapper so views can drive an `.alert(item:)` from a purchase or
/// restore outcome.
struct PurchaseAlertItem: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}
