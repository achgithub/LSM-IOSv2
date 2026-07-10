import Observation
import Foundation

/// The leagues the user has enabled (ticked in Settings). A game can use any of
/// these; Scores/Standings browse among them. How many can be enabled at once is
/// capped by the subscription (`Entitlements.leagueAllowance`): Free/No Ads = 1,
/// then 3 / 5 / 7 leagues by tier — a fixed step ladder, not the whole catalogue.
/// Persisted in UserDefaults; never empty (falls back to the home league). Observe via
/// `@Environment(EnabledLeagues.self)`.
@Observable @MainActor
final class EnabledLeagues {
    static let shared = EnabledLeagues()

    private static let key = "enabledLeagueIds"
    private static let graceStartKey = "leagueAllowanceGraceStartedAt"

    /// The grace window between first noticing an over-allowance state and
    /// the app blocking again — long enough that a lapsed card or a missed
    /// renewal isn't punished, short enough to be a real deterrent against
    /// coasting on a single month's subscription indefinitely.
    static let graceDurationDays: Double = 14

    private(set) var ids: [String]
    /// When the grace clock started — nil means either compliant, or over
    /// allowance but not yet witnessed by a launch (see `updateGracePeriod`).
    private(set) var gracePeriodStartedAt: Date?

    private init() {
        let saved = UserDefaults.standard.stringArray(forKey: Self.key) ?? []
        let valid = saved.filter { Leagues.byId($0) != nil }
        ids = valid.isEmpty ? [Leagues.home.id] : valid
        if let raw = UserDefaults.standard.object(forKey: Self.graceStartKey) as? Double {
            gracePeriodStartedAt = Date(timeIntervalSince1970: raw)
        }
    }

    /// Enabled leagues, in registry order.
    var leagues: [LeagueOption] { Leagues.all.filter { ids.contains($0.id) } }

    func isEnabled(_ league: LeagueOption) -> Bool { ids.contains(league.id) }

    func enable(_ league: LeagueOption) {
        guard !ids.contains(league.id) else { return }
        ids.append(league.id)
        persist()
    }

    /// Replace the whole enabled set with a single league (used to SWAP the one
    /// league on a single-league plan). Callers handle any game-deletion confirm.
    func setOnly(_ league: LeagueOption) {
        ids = [league.id]
        persist()
    }

    /// Disable a league. Callers handle any destructive confirmation (deleting
    /// games that reference it) before calling. Never leaves the set empty.
    func disable(_ league: LeagueOption) {
        ids.removeAll { $0 == league.id }
        if ids.isEmpty { ids = [Leagues.home.id] }
        persist()
    }

    /// Drop leagues that no longer exist (never empty). Does NOT trim for the
    /// subscription allowance — going over allowance (e.g. a cancelled sub)
    /// never immediately force-removes anything; existing games keep running
    /// regardless of tier for the full grace period (see `updateGracePeriod`).
    /// Only starting a NEW game in a not-yet-active league is gated right
    /// away (see `NewGameView`). The user can always manually disable an idle
    /// excess league in Settings (`LeagueSettingsView`).
    func pruneInvalid() {
        ids = ids.filter { Leagues.byId($0) != nil }
        if ids.isEmpty { ids = [Leagues.home.id] }
        persist()
    }

    /// True when more leagues are enabled than the current tier allows.
    func isOverAllowance(_ entitlements: Entitlements) -> Bool {
        ids.count > entitlements.leagueAllowance
    }

    /// Starts or clears the grace clock. Call once per launch (after the
    /// tier has resolved) — never on a background timer, so the clock can
    /// only ever start at a moment the manager actually had the app open to
    /// see the warning banner. A manager who doesn't open the app for two
    /// weeks (e.g. on holiday) never has the clock expire unseen: it simply
    /// hasn't started yet, and starts fresh — a full, fair 14 days — the
    /// next time they do launch. Clears the instant they're back in
    /// compliance, so any future overage always gets its own fresh window.
    func updateGracePeriod(_ entitlements: Entitlements) {
        if isOverAllowance(entitlements) {
            guard gracePeriodStartedAt == nil else { return }
            gracePeriodStartedAt = Date()
            persistGrace()
        } else if gracePeriodStartedAt != nil {
            gracePeriodStartedAt = nil
            persistGrace()
        }
    }

    /// Days left before the app blocks again, or nil when not over allowance.
    /// Rounds up so "13.2 days left" reads as "14 days left" on day one.
    func graceDaysRemaining(_ entitlements: Entitlements) -> Int? {
        guard isOverAllowance(entitlements), let start = gracePeriodStartedAt else { return nil }
        let elapsedDays = Date().timeIntervalSince(start) / 86400
        return max(0, Int((Self.graceDurationDays - elapsedDays).rounded(.up)))
    }

    /// True once the grace period has fully elapsed while still over
    /// allowance — the app blocks (via `LeagueDowngradeView`) until the
    /// manager subscribes, restores, or removes leagues back within plan.
    func mustBlock(_ entitlements: Entitlements) -> Bool {
        graceDaysRemaining(entitlements) == 0
    }

    private func persist() { UserDefaults.standard.set(ids, forKey: Self.key) }

    private func persistGrace() {
        if let gracePeriodStartedAt {
            UserDefaults.standard.set(gracePeriodStartedAt.timeIntervalSince1970, forKey: Self.graceStartKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.graceStartKey)
        }
    }
}
