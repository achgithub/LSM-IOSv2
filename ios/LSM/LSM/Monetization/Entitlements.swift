import Foundation
import Observation

/// Subscription tiers (see docs/pricing-model.md for the priced ladder).
/// RevenueCat entitlement identifiers MUST match the raw values `no_ads` /
/// `leagues_3` / `leagues_5` / `leagues_7`.
enum Tier: String, CaseIterable, Identifiable {
    case free
    case noAds = "no_ads"
    case leagues3 = "leagues_3"
    case leagues5 = "leagues_5"
    case leagues7 = "leagues_7"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .free: return AppString("Free")
        case .noAds: return AppString("No Ads")
        case .leagues3: return AppString("3 Leagues")
        case .leagues5: return AppString("5 Leagues")
        case .leagues7: return AppString("7 Leagues")
        }
    }

    var detail: String {
        switch self {
        case .free: return AppString("Ad-supported · 1 league")
        case .noAds: return AppString("Ads removed · 1 league")
        case .leagues3: return AppString("Ads removed · 3 leagues")
        case .leagues5: return AppString("Ads removed · 5 leagues")
        case .leagues7: return AppString("Ads removed · 7 leagues")
        }
    }

    /// All paid tiers remove ads (spec §ads / free-vs-sub tiers).
    var removesAds: Bool { self != .free }
}

/// App-wide entitlement state. In production the tier comes from RevenueCat; a
/// dev override lets you flip between any `Tier` on-device (ads on/off, league
/// allowance) without a real purchase (same approach as the darts
/// EntitlementsService).
@Observable @MainActor
final class Entitlements {
    static let shared = Entitlements()

    private(set) var tier: Tier = .free
    /// True once a tier has been resolved (RevenueCat or a dev override).
    private(set) var verified = false

    // RevenueCat entitlement identifiers (match the dashboard + Tier raw values).
    static let entitlementNoAds = Tier.noAds.rawValue
    static let entitlementLeagues3 = Tier.leagues3.rawValue
    static let entitlementLeagues5 = Tier.leagues5.rawValue
    static let entitlementLeagues7 = Tier.leagues7.rawValue

    private static let devTierKey = "devTierOverride"

    private init() {
        // Pre-release: restore a dev tier override so a rebuild/reinstall doesn't
        // reset testing back to Free. Production resolves via RevenueCat instead.
        #if DEBUG
        if let raw = UserDefaults.standard.string(forKey: Self.devTierKey),
           let saved = Tier(rawValue: raw) {
            tier = saved
            verified = true
        }
        #endif
    }

    /// The single gate the UI uses to decide whether to render ad placements.
    var shouldShowAds: Bool { !tier.removesAds }

    /// How many leagues the user may have enabled at once (ticked in Settings).
    /// Free / No Ads = 1, then 3 / 5 / 7 leagues by tier — a fixed step ladder,
    /// not "all leagues", so price always tracks exactly what's enabled even as
    /// the league catalogue grows past 7 (see docs/pricing-model.md). Capped at
    /// the number of leagues that actually exist so a small catalogue never
    /// claims more than it has. Change tier→count here only.
    var leagueAllowance: Int {
        switch tier {
        case .free:     return 1
        case .noAds:    return 1
        case .leagues3: return min(3, Leagues.all.count)
        case .leagues5: return min(5, Leagues.all.count)
        case .leagues7: return min(7, Leagues.all.count)
        }
    }

    /// True when the user may enable more than one league (so the Settings
    /// checklist and in-game league chooser are worth showing as multi-select).
    var canHaveMultipleLeagues: Bool { leagueAllowance > 1 }

    /// Local testing override — flips the tier with no purchase. DEBUG-only: a
    /// no-op in release builds so it can never bypass the RevenueCat entitlement
    /// (production always resolves the tier via PurchaseService).
    func setDevTier(_ tier: Tier) {
        #if DEBUG
        self.tier = tier
        self.verified = true
        UserDefaults.standard.set(tier.rawValue, forKey: Self.devTierKey)
        #endif
    }

    /// Applied by `PurchaseService` once it resolves the live entitlements.
    func apply(tier: Tier) {
        self.tier = tier
        self.verified = true
    }

    func refresh() async {
        await PurchaseService.shared.refreshTier()
    }
}
