import Combine
import SwiftUI

/// Live matches (schedule + score together) across the manager's enabled
/// leagues. A magnifier opens a search panel (league pills, team text +
/// Home/Away, matchday, date range, A–Z sort) so a manager can look things up
/// fast without leaving the app. The monetization gate is on explicit refresh
/// *actions* (see AdGate), not browsing.
struct MatchesView: View {
    @Environment(EnabledLeagues.self) private var enabled

    @State private var items: [MatchDTO] = []
    @State private var teamsById: [Int: TeamDTO] = [:]
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var lastRefreshed: Date?

    // Refresh throttle — the visible form of Rule A. While `freshUntil` is in the
    // future, every enabled league's matches are still within the 120s local TTL,
    // so nothing fresher exists to fetch: the refresh button is greyed and the
    // footer shows a countdown to when it re-enables. Applies to subscribers too —
    // matches can't be fresher than the Worker's own ~120s upstream window, so a
    // sooner tap would only burn calls for identical data. `now` ticks once a
    // second to drive the countdown and flip the button back on at zero.
    @State private var now = Date()
    @State private var freshUntil: Date?

    // Search / filter
    @State private var selectedLeagueIds: Set<String> = []
    @State private var teamQuery = ""
    @State private var homeAway: HomeAwayFilter = .all
    @State private var matchdayFilter: Int?
    @State private var dateRangeOn = false
    @State private var dateFrom = Date().addingTimeInterval(-1 * 24 * 3600)
    @State private var dateTo = Date().addingTimeInterval(14 * 24 * 3600)
    @State private var sortAZ = false
    @State private var showSearch = false

    /// Leagues currently included (defaults to every enabled league).
    private var activeLeagueIds: Set<String> {
        selectedLeagueIds.isEmpty ? Set(enabled.leagues.map(\.id)) : selectedLeagueIds
    }

    private var matchdays: [Int] { Array(Set(items.compactMap(\.matchday))).sorted() }

    private func name(_ id: Int) -> String {
        teamsById[id]?.shortName ?? teamsById[id]?.name ?? "Team \(id)"
    }

    private func teamMatches(_ item: MatchDTO) -> Bool {
        let q = teamQuery.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return true }
        let home = name(item.homeTeamId).localizedCaseInsensitiveContains(q)
        let away = name(item.awayTeamId).localizedCaseInsensitiveContains(q)
        switch homeAway {
        case .all:  return home || away
        case .home: return home
        case .away: return away
        }
    }

    private func dateInRange(_ kickoff: Date?) -> Bool {
        guard let kickoff else { return false }
        let cal = Calendar.current
        let lo = cal.startOfDay(for: dateFrom)
        let hi = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: dateTo)) ?? dateTo
        return kickoff >= lo && kickoff < hi
    }

    private var filtered: [MatchDTO] {
        let result = items.filter { item in
            (item.leagueId.map { activeLeagueIds.contains($0) } ?? false)
                && (matchdayFilter == nil || item.matchday == matchdayFilter)
                && (!dateRangeOn || dateInRange(FixtureFormat.kickoffDate(item.kickoff)))
                && teamMatches(item)
        }
        if sortAZ {
            return result.sorted { name($0.homeTeamId).localizedCaseInsensitiveCompare(name($1.homeTeamId)) == .orderedAscending }
        }
        return result.sorted(by: MatchDTO.byKickoffThenId)
    }

    private var filtersActive: Bool {
        !teamQuery.isEmpty || matchdayFilter != nil || dateRangeOn || sortAZ
            || (selectedLeagueIds.count != enabled.leagues.count && !selectedLeagueIds.isEmpty)
    }

    /// True while the refresh is throttled (all leagues fresh within TTL).
    private var isThrottled: Bool { freshUntil.map { now < $0 } ?? false }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && items.isEmpty {
                    ProgressView("Loading matches…")
                } else if let errorMessage, items.isEmpty {
                    ContentUnavailableView("Couldn't load matches", systemImage: "wifi.slash", description: Text(errorMessage))
                } else if filtered.isEmpty {
                    ContentUnavailableView(
                        "No matches",
                        systemImage: "sportscourt",
                        description: Text(items.isEmpty ? "No matches available right now." : "No matches match your search.")
                    )
                } else {
                    List(filtered) { item in
                        MatchRow(item: item, teamsById: teamsById)
                    }
                }
            }
            // The guard above only covers the true first-ever-empty load. Once
            // `items` holds anything (e.g. the enabled-league set changes and
            // `load()` re-runs, possibly re-resolving team names over the
            // network), that reload was previously silent — the list just sat
            // there unchanged for however long it took, which read as the app
            // hanging rather than working. Surface it without replacing the
            // still-valid stale content underneath.
            .safeAreaInset(edge: .top) {
                if isLoading && !items.isEmpty {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Refreshing…").font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(.bar)
                }
            }
            .appBackground()
            .navigationTitle("Matches")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSearch = true } label: {
                        Image(systemName: filtersActive ? "magnifyingglass.circle.fill" : "magnifyingglass")
                    }
                    .accessibilityLabel(filtersActive ? "Search and filters (active)" : "Search and filters")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    // Greyed while throttled (within the 120s TTL) — the footer
                    // countdown says when it re-enables. See `freshUntil`.
                    Button { refresh() } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Refresh")
                    .disabled(isLoading || isThrottled)
                }
            }
            .sheet(isPresented: $showSearch) {
                MatchesSearchSheet(
                    leagues: enabled.leagues,
                    matchdays: matchdays,
                    selectedLeagueIds: $selectedLeagueIds,
                    teamQuery: $teamQuery,
                    homeAway: $homeAway,
                    matchdayFilter: $matchdayFilter,
                    dateRangeOn: $dateRangeOn,
                    dateFrom: $dateFrom,
                    dateTo: $dateTo,
                    sortAZ: $sortAZ
                )
            }
            // Load every enabled league once; pills filter client-side so toggling
            // them is instant and never re-hits the network. Reconciled against
            // the CURRENT enabled set every time it changes, not just when
            // empty — otherwise switching leagues leaves `selectedLeagueIds`
            // pointing at a league that's no longer enabled, and every fetched
            // item gets filtered out (looks like matches "failed", but it's a
            // stale filter, not a fetch problem).
            .task(id: enabled.leagues.map(\.id)) {
                let validIds = Set(enabled.leagues.map(\.id))
                selectedLeagueIds.formIntersection(validIds)
                if selectedLeagueIds.isEmpty { selectedLeagueIds = validIds }
                await load()
            }
            // Only advance the clock while throttled, so we don't re-render (and
            // re-sort the list) every second once the button is live again. The
            // tick that crosses `freshUntil` still lands (guard sees the old
            // `now`), flips the button on, then ticking stops until the next load.
            .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { tick in
                if isThrottled { now = tick }
            }
            .safeAreaInset(edge: .bottom) { footer }
        }
    }

    // Shared footer with Standings: last-refreshed time + the non-affiliation
    // disclaimer, same look and feel.
    private var footer: some View {
        VStack(spacing: 4) {
            if let lastRefreshed {
                Text("Updated \(lastRefreshed.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if isThrottled, let freshUntil {
                let remaining = Duration.seconds(max(0, freshUntil.timeIntervalSince(now)))
                Text("Refresh available in \(remaining.formatted(.time(pattern: .minuteSecond)))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            // Single localized string key — can't wrap without changing the key.
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

    /// Refresh button across all enabled leagues. Honours the local TTL (rule A)
    /// and self-heals corruption:
    /// - every league fresh within TTL → re-show cache, **no ad, no call**;
    /// - any corrupt cache → recover with a **free** fetch (our bad data) — the bad
    ///   files have already been deleted by `read`;
    /// - otherwise (any stale / empty) → the normal ad-gated fetch.
    /// The throttle deadline comes from the shared Matches-cache clock (see
    /// `LeagueDataCache.sharedMatchesThrottleUntil`), not a separate tracker —
    /// Results entry's "Pull results from server" reads/writes the same per-league
    /// Matches cache, so pulling in one screen also throttles the other.
    private func matchesThrottleUntil() -> Date? {
        LeagueDataCache.sharedMatchesThrottleUntil(for: enabled.leagues.map(\.id))
    }

    private func refresh() {
        var anyCorrupt = false
        var allFresh = true
        for league in enabled.leagues {
            switch LeagueDataCache.read(LeagueDataCache.Matches.self, key: LeagueDataCache.matchesKey(league.id)) {
            case .hit(let cached):
                if !LeagueDataCache.isFresh(cached.date, ttl: CacheTTL.matches) { allFresh = false }
            case .empty:
                allFresh = false
            case .corrupt:
                allFresh = false
                anyCorrupt = true
            }
        }
        if allFresh {
            Task { await load() }                    // re-show cache, no ad, no network
        } else if anyCorrupt {
            Task { await load(force: true) }         // recover free
        } else {
            AdGate.run { Task { await load(force: true) } }
        }
    }

    /// Loads matches for every enabled league. `force` (the ad-gated refresh)
    /// always hits the network and overwrites the per-league cache; otherwise
    /// each league is served purely from its cache — a never-before-opened
    /// league just stays empty until an explicit gated refresh populates it.
    /// The device's one-ever free look at real data is handled once, centrally,
    /// at launch (`LeagueData.performFirstLaunchFreeFillIfNeeded`) — never
    /// lazily here, which is what previously let switching/enabling leagues
    /// bypass the gate repeatedly.
    private func load(force: Bool = false) async {
        isLoading = true
        errorMessage = nil
        var allItems: [MatchDTO] = []
        var dates: [Date] = []
        do {
            for league in enabled.leagues {
                let key = LeagueDataCache.matchesKey(league.id)
                if !force, let cached = LeagueDataCache.load(LeagueDataCache.Matches.self, key: key) {
                    allItems += cached.items
                    dates.append(cached.date)
                } else if force {
                    let leagueItems = try await LeagueData.pullLiveMatches(for: league)
                    allItems += leagueItems
                    dates.append(Date())
                }
            }
            // Fetch team names before publishing `items` — otherwise the list
            // renders with cached matches while teamsById is still empty,
            // showing "Team <id>" placeholders that flip to real names once
            // this (potentially slow, network-bound) call resolves.
            let teams = (try? await LeagueData.load(for: enabled.leagues))?.teamsById ?? teamsById
            items = allItems
            teamsById = teams
            lastRefreshed = dates.max()
        } catch {
            // Keep whatever was already loaded/cached rather than wiping a
            // screen that was showing fine just because this refresh failed
            // (e.g. maintenance mode) — matches StandingsView's same pattern.
            errorMessage = error.localizedDescription
        }
        // Re-arm the throttle from the now-current caches (greyed if all fresh).
        // Sync `now` first so the initial countdown render is accurate rather than
        // showing stale view-creation time (which inflates the display by ~load duration).
        now = Date()
        freshUntil = matchesThrottleUntil()
        isLoading = false
    }
}

// MARK: - Search panel

enum HomeAwayFilter: Hashable { case all, home, away }

private struct MatchesSearchSheet: View {
    @Environment(\.dismiss) private var dismiss
    let leagues: [LeagueOption]
    let matchdays: [Int]
    @Binding var selectedLeagueIds: Set<String>
    @Binding var teamQuery: String
    @Binding var homeAway: HomeAwayFilter
    @Binding var matchdayFilter: Int?
    @Binding var dateRangeOn: Bool
    @Binding var dateFrom: Date
    @Binding var dateTo: Date
    @Binding var sortAZ: Bool

    var body: some View {
        NavigationStack {
            Form {
                if leagues.count > 1 {
                    Section("Leagues") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(leagues) { league in leaguePill(league) }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                Section("Team") {
                    TextField("Search team", text: $teamQuery)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                    Picker("Show", selection: $homeAway) {
                        Text("All").tag(HomeAwayFilter.all)
                        Text("Home").tag(HomeAwayFilter.home)
                        Text("Away").tag(HomeAwayFilter.away)
                    }
                    .pickerStyle(.segmented)
                }

                Section("Sort") {
                    Picker("Sort", selection: $sortAZ) {
                        Text("Kick-off").tag(false)
                        Text("A–Z").tag(true)
                    }
                    .pickerStyle(.segmented)
                }

                if !matchdays.isEmpty {
                    Section("Matchday") {
                        Picker("Matchday", selection: $matchdayFilter) {
                            Text("All").tag(Int?.none)
                            ForEach(matchdays, id: \.self) { Text("MD \($0)").tag(Int?.some($0)) }
                        }
                    }
                }

                Section("Date range") {
                    Toggle("Filter by date", isOn: $dateRangeOn.animation())
                    if dateRangeOn {
                        DatePicker("From", selection: $dateFrom, displayedComponents: .date)
                        DatePicker("To", selection: $dateTo, in: dateFrom..., displayedComponents: .date)
                    }
                }

                Section {
                    Button("Clear all", role: .destructive) { clearAll() }
                }
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func leaguePill(_ league: LeagueOption) -> some View {
        let on = selectedLeagueIds.isEmpty || selectedLeagueIds.contains(league.id)
        return Button {
            toggle(league.id)
        } label: {
            Text(league.displayName)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(on ? Color.accentColor : Color.gray.opacity(0.2), in: Capsule())
                .foregroundStyle(on ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    private func toggle(_ id: String) {
        if selectedLeagueIds.contains(id) {
            if selectedLeagueIds.count > 1 { selectedLeagueIds.remove(id) }  // keep at least one
        } else {
            selectedLeagueIds.insert(id)
        }
    }

    private func clearAll() {
        selectedLeagueIds = Set(leagues.map(\.id))
        teamQuery = ""
        homeAway = .all
        matchdayFilter = nil
        dateRangeOn = false
        sortAZ = false
    }
}

// MARK: - Row

/// Match row — home tile/TLA · score · away TLA/tile, with the kick-off
/// date/time + matchday on the trailing edge. A small live indicator
/// (FT / 45' / Postp.) sits under the score.
private struct MatchRow: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    let item: MatchDTO
    let teamsById: [Int: TeamDTO]
    @State private var expanded = false

    private var isPad: Bool { sizeClass == .regular }
    private var nameFont: Font { isPad ? .title3 : .body }
    private var scoreFont: Font { isPad ? .title3 : .subheadline }
    private var centreWidth: CGFloat { isPad ? 56 : 44 }

    private func shortName(_ id: Int) -> String { teamsById[id]?.shortName ?? teamsById[id]?.name ?? "Team \(id)" }
    private func fullName(_ id: Int) -> String { teamsById[id]?.name ?? "Team \(id)" }
    private func displayName(_ id: Int) -> String { expanded ? fullName(id) : shortName(id) }

    private var scoreText: String {
        if let h = item.homeScore, let a = item.awayScore { return "\(h)–\(a)" }
        return "v"
    }

    /// Live/finished indicator shown under the score; nil for upcoming matches
    /// (their date/time already shows on the right). Routed through
    /// `AppString` (not passed to `Text` as a literal) since `Text(String)` —
    /// a runtime value, not a literal — never localizes; only `Text("…")` does.
    private var liveStatus: (text: String, color: Color)? {
        switch item.status {
        case "FINISHED":          return (AppString("FT"), .secondary)
        case "IN_PLAY", "PAUSED": return (item.minute.map { "\($0)'" } ?? AppString("LIVE"), .green)
        case "POSTPONED":         return (AppString("Postp."), .orange)
        default:                  return nil
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            // Home — name (truncates; tap the row to expand to full name).
            Text(displayName(item.homeTeamId)).font(nameFont).lineLimit(expanded ? nil : 1)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Centre — score (+ live indicator), fixed width so it stays put.
            VStack(spacing: 1) {
                Text(scoreText).font(scoreFont).bold().monospacedDigit()
                if let live = liveStatus {
                    Text(live.text).font(.caption2).foregroundStyle(live.color).lineLimit(1)
                }
            }
            .frame(width: centreWidth)

            // Away — name, mirror of home.
            Text(displayName(item.awayTeamId)).font(nameFont).lineLimit(expanded ? nil : 1)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)

            // Trailing — date / time / matchday, fixed width on the right edge.
            VStack(alignment: .trailing, spacing: 1) {
                if let kickoff = FixtureFormat.kickoffDate(item.kickoff) {
                    Text(kickoff, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                        .font(.caption2).foregroundStyle(.secondary)
                    Text(kickoff, format: .dateTime.hour().minute())
                        .font(.caption2.weight(.semibold))
                }
                if let md = item.matchday {
                    Text("MD \(md)").font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .frame(width: isPad ? 96 : 74, alignment: .trailing)
        }
        .padding(.vertical, isPad ? 4 : 0)
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() } }
    }
}
