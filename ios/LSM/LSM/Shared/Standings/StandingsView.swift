import SwiftUI

/// League table from the Worker, with §15 team tiles. Browsing is a free live
/// read; the explicit refresh button is the free-tier rewarded-ad gate (matches
/// Scores), and shows when the data was last refreshed.
struct StandingsView: View {
    @Environment(EnabledLeagues.self) private var enabled
    @State private var selectedLeague: LeagueOption?
    @State private var standings: [StandingDTO] = []
    @State private var teamsById: [Int: TeamDTO] = [:]
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var lastRefreshed: Date?

    // Refresh throttle — the visible form of Rule A (same idea as Scores, gentler
    // presentation). While `freshUntil` is in the future the table is still within
    // its 30m local TTL, and the Worker itself only re-pulls the table every 30m,
    // so a refresh couldn't fetch anything newer: the button is greyed and the
    // footer says it's up to date and roughly when it'll refresh. No ticking
    // countdown (a 30m timer would feel punitive) — a one-shot task just flips the
    // button back on at `freshUntil`; `now` exists only to trigger that re-render.
    @State private var now = Date()
    @State private var freshUntil: Date?

    /// True while the refresh is throttled (table fresh within its 30m TTL).
    private var isThrottled: Bool { freshUntil.map { now < $0 } ?? false }

    private var league: LeagueOption { selectedLeague ?? enabled.leagues.first ?? Leagues.home }
    private var leagueBinding: Binding<LeagueOption> {
        Binding(get: { league }, set: { selectedLeague = $0 })
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && standings.isEmpty {
                    ProgressView("Loading standings…")
                } else if let errorMessage, standings.isEmpty {
                    ContentUnavailableView(
                        "Couldn't load standings",
                        systemImage: "wifi.slash",
                        description: Text(errorMessage)
                    )
                } else {
                    List(standings) { row in
                        StandingRow(row: row, team: teamsById[row.teamId])
                    }
                }
            }
            .appBackground()
            .navigationTitle("Standings")
            .toolbar {
                if enabled.leagues.count > 1 {
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            Picker("League", selection: leagueBinding) {
                                ForEach(enabled.leagues) { Text($0.name).tag($0) }
                            }
                        } label: {
                            Label(league.displayName, systemImage: "trophy")
                        }
                    }
                } else {
                    ToolbarItem(placement: .principal) {
                        Text(league.name).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    // Refresh on the trailing edge to match Scores. Same gate: a
                    // fresh pull is a server fetch, so free users watch a rewarded
                    // ad first (see AdGate); subscribers refresh instantly. Greyed
                    // while within the 30m TTL — nothing newer exists to fetch —
                    // with a footer note saying when it re-enables. See refresh().
                    Button { refresh() } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isLoading || isThrottled)
                }
            }
            // Reloads when the chosen league changes (browsing, so not ad-gated —
            // the explicit refresh button is the gated fetch action).
            .task(id: league) { await load(force: false) }
            // One-shot: wake exactly when the throttle lapses to flip the button
            // back on (and immediately if it already has, e.g. on tab re-entry).
            .task(id: freshUntil) {
                guard let freshUntil else { return }
                let remaining = freshUntil.timeIntervalSinceNow
                if remaining > 0 { try? await Task.sleep(for: .seconds(remaining)) }
                now = Date()
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 4) {
                    if let lastRefreshed {
                        Text("Updated \(lastRefreshed.formatted(date: .omitted, time: .shortened))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if isThrottled, let freshUntil {
                        Text("Up to date · refresh available ~\(freshUntil.formatted(date: .omitted, time: .shortened))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    // Independence / non-affiliation disclaimer (names + data are
                    // factual, descriptive use only). Single localized key — can't wrap.
                    // swiftlint:disable:next line_length
                    Text("Not affiliated with, licensed by or endorsed by any football club, league or federation. An independent tool — team names and fixtures are factual data shown for reference only.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }
                .padding(.bottom, 6)
                .background(.bar)
            }
        }
    }

    /// Refresh button. Honours the local TTL (rule A) and self-heals corruption:
    /// - fresh within TTL → re-show cache, **no ad, no Worker call**;
    /// - corrupt cache → recover with a **free** fetch (our bad data, not a paid
    ///   refresh) — `read` has already deleted the bad file;
    /// - stale / empty → the normal ad-gated fetch.
    /// The throttle deadline: when a refresh could next fetch a newer table.
    /// `nil` (refresh available now) if the table is stale, empty or corrupt — a
    /// refresh would then do real work; otherwise the cache date + the 30m TTL.
    private func standingsThrottleUntil() -> Date? {
        switch LeagueDataCache.read(LeagueDataCache.Standings.self, key: LeagueDataCache.standingsKey(league.id)) {
        case .hit(let cached) where LeagueDataCache.isFresh(cached.date, ttl: CacheTTL.standings):
            return cached.date.addingTimeInterval(CacheTTL.standings)
        case .hit, .empty, .corrupt:
            return nil
        }
    }

    private func refresh() {
        let key = LeagueDataCache.standingsKey(league.id)
        switch LeagueDataCache.read(LeagueDataCache.Standings.self, key: key) {
        case .hit(let cached) where LeagueDataCache.isFresh(cached.date, ttl: CacheTTL.standings):
            standings = cached.rows
            teamsById = Dictionary(cached.teams.map { ($0.externalId, $0) }, uniquingKeysWith: { first, _ in first })
            lastRefreshed = cached.date
        case .corrupt:
            Task { await load(force: true) }
        case .hit, .empty:
            AdGate.run { Task { await load(force: true) } }
        }
    }

    /// `force` (the ad-gated refresh) hits the network and overwrites the cache;
    /// otherwise the league is served from its cache, fetching only the first time
    /// (empty/corrupt cache) — so a relaunch isn't a free refresh.
    private func load(force: Bool) async {
        isLoading = true
        errorMessage = nil
        let key = LeagueDataCache.standingsKey(league.id)
        if !force, let cached = LeagueDataCache.load(LeagueDataCache.Standings.self, key: key) {
            standings = cached.rows
            teamsById = Dictionary(cached.teams.map { ($0.externalId, $0) }, uniquingKeysWith: { first, _ in first })
            lastRefreshed = cached.date
            freshUntil = standingsThrottleUntil()
            isLoading = false
            return
        }
        let client = league.client
        do {
            async let standingsReq = client.standings()
            async let teamsReq = client.teams()
            let (rows, teams) = try await (standingsReq, teamsReq)
            standings = rows
            teamsById = Dictionary(teams.map { ($0.externalId, $0) }, uniquingKeysWith: { first, _ in first })
            let now = Date()
            lastRefreshed = now
            LeagueDataCache.save(LeagueDataCache.Standings(date: now, rows: rows, teams: teams), key: key)
        } catch {
            errorMessage = error.localizedDescription
        }
        // Re-arm the throttle from the now-current cache (greyed if fresh).
        freshUntil = standingsThrottleUntil()
        isLoading = false
    }
}

private struct StandingRow: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    let row: StandingDTO
    let team: TeamDTO?
    @State private var expanded = false

    private var isPad: Bool { sizeClass == .regular }
    private var nameFont: Font { isPad ? .title3 : .body }
    // Short name by default (consistent with Scores/Fixtures); tap to expand to
    // the full name for long ones (e.g. Wolverhampton).
    private var shortName: String { team?.shortName ?? team?.name ?? "Team \(row.teamId)" }
    private var fullName: String { team?.name ?? team?.shortName ?? "Team \(row.teamId)" }

    var body: some View {
        HStack(spacing: isPad ? 16 : 12) {
            Text("\(row.position)")
                .font(nameFont)
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(width: isPad ? 40 : 28, alignment: .leading)
                .foregroundStyle(.secondary)
            Text(expanded ? fullName : shortName)
                .font(nameFont)
                .lineLimit(expanded ? nil : 1)
            Spacer()
            // Played / Won / Drawn / Lost — labelled + larger on iPad.
            HStack(spacing: isPad ? 18 : 10) {
                stat("P", row.played)
                stat("W", row.won)
                stat("D", row.drawn)
                stat("L", row.lost)
            }
            Text("\(row.points)")
                .bold()
                .frame(width: isPad ? 48 : 32, alignment: .trailing)
                .font(nameFont)
                .monospacedDigit()
        }
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() } }
        .padding(.vertical, isPad ? 6 : 0)
    }

    private func stat(_ label: LocalizedStringKey, _ value: Int) -> some View {
        VStack(spacing: 1) {
            Text(label)
                .font(isPad ? .caption2 : .system(size: 8))
                .foregroundStyle(.tertiary)
            Text("\(value)")
                .font(isPad ? .callout : .caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: isPad ? 24 : 14)
    }
}
