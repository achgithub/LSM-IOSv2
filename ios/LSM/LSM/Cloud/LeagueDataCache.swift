import Foundation

/// Local cache freshness windows, per resource. Inside a resource's TTL the app
/// answers from its own on-disk cache and never calls the Worker — so exploring
/// the app (relaunching, tab-switching, re-tapping refresh) can't generate
/// wasteful Worker traffic. Tuned here in one place; safe to tweak post-launch
/// from real usage without touching any logic.
///
/// These are *local* TTLs (Worker-call suppression). They are deliberately
/// separate from the revenue gate (AdGate) and from the Worker's own upstream
/// TTLs (a later pass).
enum CacheTTL {
    /// Live match state changes minute-to-minute. 120s (not 60) to discourage
    /// constant-refresh misuse at scale — matches the Worker's own
    /// SCORE_TTL_SECONDS, which can't return anything fresher anyway. This is
    /// the hard local TTL: an explicit refresh tap inside this window is a
    /// no-op (Rule A), gated or not.
    static let matches: TimeInterval = 120
    /// The table only moves when matches finish.
    static let standings: TimeInterval = 30 * 60
    /// Names / promotions change at most seasonally.
    static let teams: TimeInterval = 7 * 24 * 60 * 60

    /// App-side staleness threshold for auto-assign: if the held table is older
    /// than this, offer a (gated) refresh before assigning bottom-of-table. A
    /// different job from `standings` above, so a different number on purpose.
    static let autoAssignTableStale: TimeInterval = 60 * 60
    /// UX-only courtesy threshold for the Fixtures view (Open Round / New Game /
    /// Picks) — much longer than `matches` above, since the schedule barely
    /// moves and constantly nagging every two minutes would be absurd for a
    /// browse-and-pick flow. Crossing this just offers a refresh; it isn't a
    /// hard cutoff, and accepting still goes through the same Matches ad gate
    /// as the Scores tab — there's no separate free path for fixtures.
    static let fixturesCourtesyAge: TimeInterval = 12 * 60 * 60
}

/// On-disk cache for per-league sports data, so browsing the Matches / Standings
/// screens and running rounds shows the last fetched data without hitting the
/// network. The explicit, ad-gated refresh fetches fresh gated data (matches,
/// table) and overwrites the cache; a fresh launch reads the cache rather than
/// re-fetching — closing the "relaunch for a free refresh" back door.
enum LeagueDataCache {
    /// One league's matches snapshot — schedule (matchday/kickoff) and live
    /// state (status/score/minute/winner) together, one record per match, one
    /// cache, one timestamp. Previously split across a separate Fixtures cache
    /// (schedule, free) and Scores cache (live state, gated), which had to be
    /// reconciled after the fact whenever a live pull found a newly-FINISHED
    /// match. One unified cache means there's nothing left to reconcile.
    struct Matches: Codable {
        let date: Date
        let items: [MatchDTO]
    }

    /// One league's standings snapshot.
    struct Standings: Codable {
        let date: Date
        let rows: [StandingDTO]
        let teams: [TeamDTO]
    }

    /// One league's teams snapshot — functional/free, near-static data.
    struct Teams: Codable {
        let date: Date
        let items: [TeamDTO]
    }

    /// Outcome of a cache read. Distinguishes "nothing cached yet" (normal first
    /// run) from "a file was there but unreadable" (corrupt write, or written by
    /// an older app version whose schema no longer decodes). Lets callers recover
    /// from corruption with a free fetch instead of an ad — it's our bad data, not
    /// a user-requested refresh.
    enum Read<T> {
        case hit(T)
        case empty
        case corrupt
    }

    private static let directory: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("LeagueData", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static func url(_ key: String) -> URL {
        directory.appendingPathComponent("\(key).json")
    }

    /// Health-checked read: if a file exists but won't decode (corrupt or an old
    /// schema), it's **deleted on the spot** — so it can't linger, be half-read,
    /// or trip us again — and `.corrupt` is returned so the caller can recover
    /// with a free fetch rather than gating it behind an ad.
    static func read<T: Decodable>(_ type: T.Type, key: String) -> Read<T> {
        let fileURL = url(key)
        guard let data = try? Data(contentsOf: fileURL) else { return .empty }
        guard let value = try? JSONDecoder().decode(T.self, from: data) else {
            try? FileManager.default.removeItem(at: fileURL)
            return .corrupt
        }
        return .hit(value)
    }

    /// Convenience that collapses `read` to an optional (corrupt → nil, and the
    /// bad file is still deleted by `read`). Use `read` directly where you need to
    /// tell corruption apart from a normal first-run miss.
    static func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        if case .hit(let value) = read(type, key: key) { return value }
        return nil
    }

    static func save<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: url(key), options: .atomic)
    }

    /// True when a snapshot's timestamp is within the given local TTL — i.e. the
    /// app can serve it without calling the Worker (see `CacheTTL`).
    static func isFresh(_ date: Date, ttl: TimeInterval) -> Bool {
        Date().timeIntervalSince(date) < ttl
    }

    /// The device's single free data fill, ever — see
    /// docs/data-refresh-and-caching.md: "Single exception: first install...
    /// Period." Explicitly NOT per-league and NOT checked lazily from inside
    /// any screen (that's what let switching/enabling leagues bypass the gate
    /// repeatedly, before this fix). The only place this is ever consumed is
    /// the one explicit, centralized bootstrap at launch
    /// (`LeagueData.performFirstLaunchFreeFillIfNeeded`), which fills Matches
    /// + Standings for the home league only — never anywhere else.
    private static let freeFillUsedKey = "hasUsedFreeDataFill"

    static var hasUsedFreeFill: Bool {
        UserDefaults.standard.bool(forKey: freeFillUsedKey)
    }

    static func consumeFreeFill() {
        UserDefaults.standard.set(true, forKey: freeFillUsedKey)
    }

    static func matchesKey(_ leagueId: String) -> String { "matches-\(leagueId)" }
    static func standingsKey(_ leagueId: String) -> String { "standings-\(leagueId)" }
    static func teamsKey(_ leagueId: String) -> String { "teams-\(leagueId)" }

    /// The soonest moment a live pull (Matches tab or Results entry) could
    /// fetch something newer for this league — just the Matches cache's own
    /// timestamp against its TTL. `nil` once that window has lapsed (a pull is
    /// available now). No separate tracking struct needed: there's one cache,
    /// so its own timestamp IS the throttle clock — both Matches tab and
    /// Results entry's "Pull from server" read the same file, so a pull from
    /// either one naturally throttles the other too.
    static func matchesThrottleUntil(_ leagueId: String) -> Date? {
        guard let cached = load(Matches.self, key: matchesKey(leagueId)),
              isFresh(cached.date, ttl: CacheTTL.matches) else { return nil }
        return cached.date.addingTimeInterval(CacheTTL.matches)
    }

    /// Shared cooldown across every screen that pulls live match data (Matches
    /// tab, Results entry). `nil` (pull available now) if any league hasn't
    /// been pulled yet or its window has lapsed; otherwise the earliest expiry
    /// across the given leagues.
    static func sharedMatchesThrottleUntil(for leagueIds: [String]) -> Date? {
        var earliest: Date?
        for id in leagueIds {
            guard let expiry = matchesThrottleUntil(id) else { return nil }
            earliest = earliest.map { min($0, expiry) } ?? expiry
        }
        return earliest
    }
}
