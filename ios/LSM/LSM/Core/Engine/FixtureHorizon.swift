import Foundation

/// Rolling fixture-visibility horizon — a shared, mode-agnostic gate every
/// game mode's round-open path goes through (LMS, Predictor, and any mode
/// added later). Exists to close a subscription-abuse loophole: without it, a
/// manager could subscribe, open rounds for the whole season in one sitting,
/// let players fill in every pick/prediction, then cancel — getting a full
/// season's value from one month's fee.
///
/// Deliberately clusters by actual kickoff **date**, not by matchday number —
/// a matchday stops being an atomic weekend the moment a fixture is
/// rearranged (postponed weeks later, or brought forward for TV), which
/// happens constantly in real football calendars. A rearranged fixture just
/// falls into whichever cluster its current date puts it in, often becoming
/// a cluster of one that opens on its own schedule.
///
/// Floor/target/ceiling (21/28/35 days ≈ 3/4/5 weeks) were sized from
/// research into top-league fixture-confirmation lead times (PL ~5-6wk,
/// La Liga 3-5wk batches, Serie A 4-8wk, Bundesliga stepwise blocks). The
/// floor is intentionally a soft target, not enforced by ever extending past
/// the ceiling: some leagues (Bundesliga especially) simply haven't
/// published dates that far out yet, and there's nothing to open early —
/// see `eligibleIds` below.
///
/// **The window is anchored to the earliest available fixture, not to
/// today's calendar date.** Anchoring to "now" zeroes out every fixture
/// during close season (next ball can be 6+ weeks away) or shortchanges a
/// blend where one league's season starts later than another's. Anchoring
/// to the first fixture instead means the manager always sees a normal
/// 3-5-week window measured from whenever football next actually happens,
/// never nothing at all. For a blended (multi-league) game the anchor is
/// shared across the whole blend (the earliest fixture over every league
/// combined) — clustering itself still happens per league (see
/// `eligibleFixtureIds`), only the target/ceiling reference point is shared,
/// so one league's later start doesn't strand it behind its own separate
/// clock.
enum FixtureHorizon {
    struct Config {
        var targetDays: Double = 28
        var ceilingDays: Double = 35
        /// Fixtures within this many days of each other cluster into one
        /// "round" purely by kickoff date, independent of matchday label.
        var clusterGapDays: Double = 3

        static let `default` = Config()
    }

    /// Fixture ids eligible to go into a new round right now, unioned across
    /// every league present in `fixtures`. A fixture with no parseable
    /// kickoff (the league hasn't confirmed a date that far out yet) is
    /// never eligible — skipped, not defaulted to some placeholder date.
    static func eligibleFixtureIds(fixtures: [MatchDTO], now: Date = .now, config: Config = .default) -> Set<Int> {
        let anchor = horizonAnchor(fixtures: fixtures, now: now)
        var result: Set<Int> = []
        for (leagueId, leagueFixtures) in Dictionary(grouping: fixtures, by: { $0.leagueId }) {
            guard leagueId != nil else { continue }
            result.formUnion(eligibleIds(in: leagueFixtures, anchor: anchor, config: config))
        }
        return result
    }

    /// The furthest kickoff date currently open for one league — for display
    /// ("fixtures open through 4 Aug") and for capping a manual date-range
    /// picker. Nil if the league has no eligible dated fixtures right now.
    /// `fixtures` should be the full blended pool (every league in the
    /// game), same as `eligibleFixtureIds`, so the anchor matches.
    static func horizonEnd(leagueId: String, fixtures: [MatchDTO], now: Date = .now, config: Config = .default) -> Date? {
        let anchor = horizonAnchor(fixtures: fixtures, now: now)
        let leagueFixtures = fixtures.filter { $0.leagueId == leagueId }
        let ids = eligibleIds(in: leagueFixtures, anchor: anchor, config: config)
        guard !ids.isEmpty else { return nil }
        return leagueFixtures
            .filter { ids.contains($0.id) }
            .compactMap { FixtureFormat.kickoffDate($0.kickoff) }
            .max()
    }

    /// The earliest upcoming (>= `now`) kickoff across every league in
    /// `fixtures` — the shared reference point target/ceiling count from.
    /// Falls back to `now` itself if nothing upcoming is dated at all (then
    /// behaves exactly as a now-anchored window would).
    private static func horizonAnchor(fixtures: [MatchDTO], now: Date) -> Date {
        fixtures
            .compactMap { FixtureFormat.kickoffDate($0.kickoff) }
            .filter { $0 >= now }
            .min() ?? now
    }

    /// The furthest kickoff a hand-typed manual fixture (`ManualFixtureService`)
    /// may carry to still be admitted into a round right now — same ceiling as
    /// real fixtures, anchored off the game's real leagues only (never off
    /// other manual fixtures, so a manager can't game the anchor by typing in
    /// a fixture dated far away). Closes issue #15: without this, manual entry
    /// was a full structural bypass of the horizon, since manual fixtures were
    /// excluded from the real-fixture eligibility check entirely and admitted
    /// unconditionally regardless of date.
    ///
    /// No floor/target — only the ceiling applies. A manual entry correcting
    /// or replaying an already-admitted real fixture (e.g. one postponed
    /// weeks ago) must stay admittable no matter how far in the past its
    /// date now sits; only the "how far into the future" direction is the
    /// abuse vector this closes.
    static func manualFixtureCeiling(realFixtures: [MatchDTO], now: Date = .now, config: Config = .default) -> Date {
        horizonAnchor(fixtures: realFixtures, now: now).addingTimeInterval(config.ceilingDays * 86400)
    }

    // MARK: - Core algorithm (one league's worth of fixtures)

    private static func eligibleIds(in fixtures: [MatchDTO], anchor: Date, config: Config) -> Set<Int> {
        let dated = fixtures
            .compactMap { f -> (id: Int, date: Date)? in
                guard let date = FixtureFormat.kickoffDate(f.kickoff) else { return nil }
                return (id: f.id, date: date)
            }
            .sorted { $0.date < $1.date }
        guard !dated.isEmpty else { return [] }

        let targetEnd = anchor.addingTimeInterval(config.targetDays * 86400)
        let ceilingEnd = anchor.addingTimeInterval(config.ceilingDays * 86400)

        var admitted: [Int] = []
        for cluster in cluster(dated, gapDays: config.clusterGapDays) {
            guard let clusterEnd = cluster.map(\.date).max() else { continue }
            if clusterEnd <= targetEnd {
                admitted.append(contentsOf: cluster.map(\.id))
                continue
            }
            // First cluster to cross the target: include it whole only if
            // doing so still respects the ceiling, then stop regardless —
            // never split a cluster, never look further than the boundary.
            if clusterEnd <= ceilingEnd {
                admitted.append(contentsOf: cluster.map(\.id))
            }
            break
        }
        return Set(admitted)
    }

    /// Groups kickoff-sorted fixtures into clusters wherever the gap to the
    /// next fixture exceeds `gapDays` (covers a normal Fri–Mon round; splits
    /// off an outlier rearranged fixture into its own cluster).
    private static func cluster(_ dated: [(id: Int, date: Date)], gapDays: Double) -> [[(id: Int, date: Date)]] {
        var clusters: [[(id: Int, date: Date)]] = []
        var current: [(id: Int, date: Date)] = []
        for item in dated {
            if let lastDate = current.last?.date, item.date.timeIntervalSince(lastDate) > gapDays * 86400 {
                clusters.append(current)
                current = []
            }
            current.append(item)
        }
        if !current.isEmpty { clusters.append(current) }
        return clusters
    }
}
