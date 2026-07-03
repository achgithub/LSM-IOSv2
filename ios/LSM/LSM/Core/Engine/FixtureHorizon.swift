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
        var result: Set<Int> = []
        for (leagueId, leagueFixtures) in Dictionary(grouping: fixtures, by: { $0.leagueId }) {
            guard leagueId != nil else { continue }
            result.formUnion(eligibleIds(in: leagueFixtures, now: now, config: config))
        }
        return result
    }

    /// The furthest kickoff date currently open for one league — for display
    /// ("fixtures open through 4 Aug") and for capping a manual date-range
    /// picker. Nil if the league has no eligible dated fixtures right now.
    static func horizonEnd(leagueId: String, fixtures: [MatchDTO], now: Date = .now, config: Config = .default) -> Date? {
        let leagueFixtures = fixtures.filter { $0.leagueId == leagueId }
        let ids = eligibleIds(in: leagueFixtures, now: now, config: config)
        guard !ids.isEmpty else { return nil }
        return leagueFixtures
            .filter { ids.contains($0.id) }
            .compactMap { FixtureFormat.kickoffDate($0.kickoff) }
            .max()
    }

    // MARK: - Core algorithm (one league's worth of fixtures)

    private static func eligibleIds(in fixtures: [MatchDTO], now: Date, config: Config) -> Set<Int> {
        let dated = fixtures
            .compactMap { f -> (id: Int, date: Date)? in
                guard let date = FixtureFormat.kickoffDate(f.kickoff) else { return nil }
                return (id: f.id, date: date)
            }
            .sorted { $0.date < $1.date }
        guard !dated.isEmpty else { return [] }

        let targetEnd = now.addingTimeInterval(config.targetDays * 86400)
        let ceilingEnd = now.addingTimeInterval(config.ceilingDays * 86400)

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
