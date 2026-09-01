import Foundation

/// Client-driven auto-refresh for paying tiers — see
/// docs/sync-refresh-policy.md for the full design and rationale. **V2 only**:
/// wired from `V2RootView` (foreground) and `V2PreviewMenuView`/Home
/// (`.onAppear` + the live-poll loop). V1 (`RootTabView`,
/// `Shared/Rounds/OpenRoundView`, `Modes/Killer/Rounds/KillerOpenRoundView`)
/// is untouched and keeps today's manual, `AdGate`-only behavior.
///
/// Every call here is triggered by the client — app foreground, Home
/// appearing, the live-poll loop re-checking every 60s — never a
/// server-side timer. That's a hard constraint, not a preference: Free's
/// entire CF-cost-recovery model depends on `AdGate` being the only thing
/// that can trigger a Worker call for that tier. `refreshIfDue` guards on
/// `removesAds` itself as a convenience (so callers don't have to
/// remember to check), but `AdGate` remains the real, separate gate for
/// Free's own manual-refresh path — nothing here replaces it.
@MainActor
@Observable
final class SyncScheduler {
    static let shared = SyncScheduler()
    private init() {}

    /// True while a refresh triggered by this scheduler is in flight — Home's
    /// sync indicator binds a spin animation to this. Distinct from any
    /// screen's own `isLoading` (e.g. `MatchesStoreV2`), which covers the
    /// manual/ad-gated path and shouldn't spin for background auto-refreshes.
    private(set) var isSyncing = false

    /// True when any of `games`' current open rounds has a fixture in the
    /// active window — see docs/sync-refresh-policy.md "Active window
    /// definition." A fixture qualifies once `now >= kickoff - liveWindowLead`
    /// and stays qualified until it's finished/postponed; there's no upper
    /// time bound, so a delayed or extra-time match is never dropped early.
    /// Pure read over already-cached data — never fetches, safe to call as
    /// often as needed (e.g. every tick of the live-poll loop) with no CF
    /// cost.
    static func isAnyFixtureActive(games: [Game]) -> Bool {
        let now = Date()
        for game in games {
            guard let round = game.currentRound, round.status != .closed, !round.fixtureIds.isEmpty else { continue }
            for league in game.leagues {
                guard case .hit(let cached) = LeagueDataCache.read(
                    LeagueDataCache.Matches.self,
                    key: LeagueDataCache.matchesKey(league.id)
                ) else { continue }
                for fixture in cached.items where round.fixtureIds.contains(fixture.id) {
                    guard !fixture.isFinished, !fixture.isPostponedOrCancelled else { continue }
                    guard let kickoff = FixtureFormat.kickoffDate(fixture.kickoff) else { continue }
                    if now >= kickoff.addingTimeInterval(-CacheTTL.liveWindowLead) { return true }
                }
            }
        }
        return false
    }

    /// The relaxed + tightened ladder. Call from V2 app-foreground and Home
    /// `.onAppear`/the live-poll loop. No-ops for Free (`removesAds` guard) —
    /// Free's only refresh path stays the manual, `AdGate`-gated button.
    ///
    /// Mirrors the TTL-check-then-fetch pattern already used by
    /// `MatchesStoreV2`/`StandingsStore` (`pullLiveMatches`/
    /// `refreshStandings` always hit the network when called — the caller,
    /// not those functions, decides whether a call is due).
    func refreshIfDue(games: [Game], leagues: [LeagueOption], entitlements: Entitlements) async {
        guard entitlements.tier.removesAds, !leagues.isEmpty else { return }
        isSyncing = true
        defer { isSyncing = false }

        let liveWindowActive = Self.isAnyFixtureActive(games: games)

        await withTaskGroup(of: Void.self) { group in
            for league in leagues {
                group.addTask { @MainActor in
                    // Matches only auto-refresh while a fixture is actually
                    // in its active window — never on the shared 120s
                    // `matches` clock unconditionally. That clock stays
                    // reserved for the manual refresh tap (Fixtures tab /
                    // Results entry); this ladder polls at the much slower
                    // `matchesLiveWindow` cadence, and not at all otherwise.
                    guard liveWindowActive else { return }
                    let key = LeagueDataCache.matchesKey(league.id)
                    let cached = LeagueDataCache.load(LeagueDataCache.Matches.self, key: key)
                    guard cached == nil || !LeagueDataCache.isFresh(cached!.date, ttl: CacheTTL.matchesLiveWindow) else { return }
                    _ = try? await LeagueData.pullLiveMatches(for: league)
                }
                group.addTask { @MainActor in
                    let key = LeagueDataCache.standingsKey(league.id)
                    let cached = LeagueDataCache.load(LeagueDataCache.Standings.self, key: key)
                    let ttl = liveWindowActive ? CacheTTL.standingsLiveWindow : CacheTTL.standings
                    guard cached == nil || !LeagueDataCache.isFresh(cached!.date, ttl: ttl) else { return }
                    await LeagueData.refreshStandings(for: [league])
                }
            }
        }
    }
}
