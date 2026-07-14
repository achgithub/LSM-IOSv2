import Foundation
import Observation

/// Cloud feature level derived from tier. Backup and PWA both unlock
/// together at `leagues_3` — quantity caps (`maxActiveGames`, `maxPWALinks`)
/// do the differentiation above that point, not a feature split.
enum CloudLevel {
    case none
    case full
}

/// Subscription tiers (see docs/pricing-model.md for the full priced ladder).
/// Tier names and RevenueCat entitlement identifiers are fixed to the raw values:
/// `no_ads` / `leagues_3` / `leagues_5` / `leagues_7`.
///
/// Caps follow the 1 league : 3 active games : 20 PWA links ratio.
/// Active games = games with status `.setup` or `.active` (not `.complete`).
/// Tournament-type games are excluded from the cap by design (periodic events).
enum Tier: String, CaseIterable, Identifiable {
    case free
    case noAds    = "no_ads"
    case leagues3 = "leagues_3"
    case leagues5 = "leagues_5"
    case leagues7 = "leagues_7"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .free:     return AppString("Free")
        case .noAds:    return AppString("No Ads")
        case .leagues3: return AppString("3 Leagues")
        case .leagues5: return AppString("5 Leagues")
        case .leagues7: return AppString("7 Leagues")
        }
    }

    /// Short description for paywall and settings screens — reflects the full
    /// value bundle at each tier (leagues, games, PWA links, cloud features).
    var detail: String {
        switch self {
        case .free:
            return AppString("Ad-supported · 1 league · 2 games")
        case .noAds:
            return AppString("No ads · 1 league · 3 games")
        case .leagues3:
            return AppString("No ads · 3 leagues · 9 games · Cloud backup & PWA (60 links)")
        case .leagues5:
            return AppString("No ads · 5 leagues · 15 games · Cloud backup & PWA (100 links)")
        case .leagues7:
            return AppString("No ads · 7 leagues · 21 games · Cloud backup & PWA (140 links)")
        }
    }

    /// Maximum simultaneous non-completed games (1:3 ratio per league).
    /// Games with `.complete` status do not count against this limit.
    var maxActiveGames: Int {
        switch self {
        case .free:     return 2
        case .noAds:    return 3
        case .leagues3: return 9
        case .leagues5: return 15
        case .leagues7: return 21
        }
    }

    /// Maximum total PWA player links minted across all games combined (1:20 ratio
    /// per league). `nil` means PWA is unavailable at this tier.
    var maxPWALinks: Int? {
        switch self {
        case .free, .noAds: return nil
        case .leagues3:     return 60
        case .leagues5:     return 100
        case .leagues7:     return 140
        }
    }

    /// Cloud features (Backup, PWA) bundled into every league tier.
    var cloudLevel: CloudLevel {
        switch self {
        case .free, .noAds:               return .none
        case .leagues3, .leagues5, .leagues7: return .full
        }
    }

    /// How many leagues the user may have enabled at once. Capped at the number
    /// that actually exist so a small catalogue never claims more than it has.
    var leagueAllowance: Int {
        switch self {
        case .free, .noAds: return 1
        case .leagues3:     return min(3, Leagues.all.count)
        case .leagues5:     return min(5, Leagues.all.count)
        case .leagues7:     return min(7, Leagues.all.count)
        }
    }

    /// All paid tiers remove ads.
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

    /// How many leagues the user may have enabled at once. Passthrough to
    /// `tier.leagueAllowance` — capped at the actual catalogue size.
    var leagueAllowance: Int { tier.leagueAllowance }

    /// True when the user may enable more than one league (so the Settings
    /// checklist and in-game league chooser are worth showing as multi-select).
    var canHaveMultipleLeagues: Bool { leagueAllowance > 1 }

    /// Maximum non-completed games the user may run simultaneously.
    /// Passthrough to `tier.maxActiveGames` — enforce at game creation.
    var maxActiveGames: Int { tier.maxActiveGames }

    /// Maximum PWA player links that may be minted across all games combined.
    /// `nil` means PWA is unavailable at the current tier.
    var maxPWALinks: Int? { tier.maxPWALinks }

    /// Gates all cloud features (Backup, PWA). True when the tier
    /// includes cloud — `leagues_3` and above.
    var canUseCloud: Bool { tier.cloudLevel == .full }

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
        // Fire-and-forget — the server has no other way to learn a manager's
        // PWA link cap (tier is a client-side/StoreKit concept), and needs it
        // for the over-cap cascade cron. See ManagerLifecycleClient.
        let maxPWALinks = tier.maxPWALinks
        Task { await ManagerLifecycleClient.shared.reportEntitlements(maxPWALinks: maxPWALinks) }
    }

    func refresh() async {
        await PurchaseService.shared.refreshTier()
    }
}
