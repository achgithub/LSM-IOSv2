import Combine
import SwiftUI

/// Card-based restyle of `MatchesView` ("Fixtures" in the V2 menu) with
/// inline filter chips instead of the sheet-based search panel — every
/// filter dimension and invariant is preserved from v1 (see `MatchesView`):
/// empty `selectedLeagueIds` means "all enabled leagues", never allow
/// emptying to zero, and the enabled-league-set reconciliation task.
struct MatchesViewV2: View {
    @Environment(EnabledLeagues.self) private var enabled
    @State private var store = MatchesStoreV2()

    // Filter state — same shape/defaults as v1's MatchesView.
    @State private var selectedLeagueIds: Set<String> = []
    @State private var teamQuery = ""
    @State private var homeAway: HomeAwayFilter = .all
    @State private var matchdayFilter: Int?
    @State private var dateRangeOn = false
    @State private var dateFrom = Date().addingTimeInterval(-1 * 24 * 3600)
    @State private var dateTo = Date().addingTimeInterval(14 * 24 * 3600)
    @State private var sortAZ = false

    // Recomputed filteredItems (not a bare per-render computed var — a full
    // season's worth of matches makes that a real per-render cost) via
    // .onChange on a Hashable key bundling every filter dimension + items.
    @State private var filteredItems: [MatchDTO] = []

    private struct FilterKey: Hashable {
        var leagueIds: Set<String>
        var teamQuery: String
        var homeAway: HomeAwayFilter
        var matchdayFilter: Int?
        var dateRangeOn: Bool
        var dateFrom: Date
        var dateTo: Date
        var sortAZ: Bool
        var itemsCount: Int
        var teamsCount: Int
    }

    private var filterKey: FilterKey {
        FilterKey(
            leagueIds: selectedLeagueIds, teamQuery: teamQuery, homeAway: homeAway,
            matchdayFilter: matchdayFilter, dateRangeOn: dateRangeOn, dateFrom: dateFrom, dateTo: dateTo,
            sortAZ: sortAZ, itemsCount: store.items.count, teamsCount: store.teamsById.count
        )
    }

    private var activeLeagueIds: Set<String> {
        selectedLeagueIds.isEmpty ? Set(enabled.leagues.map(\.id)) : selectedLeagueIds
    }

    private var matchdays: [Int] { Array(Set(store.items.compactMap(\.matchday))).sorted() }

    private func name(_ id: Int) -> String {
        store.teamsById[id]?.shortName ?? store.teamsById[id]?.name ?? "Team \(id)"
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

    private func recomputeFiltered() {
        let result = store.items.filter { item in
            (item.leagueId.map { activeLeagueIds.contains($0) } ?? false)
                && (matchdayFilter == nil || item.matchday == matchdayFilter)
                && (!dateRangeOn || dateInRange(FixtureFormat.kickoffDate(item.kickoff)))
                && teamMatches(item)
        }
        filteredItems = sortAZ
            ? result.sorted { name($0.homeTeamId).localizedCaseInsensitiveCompare(name($1.homeTeamId)) == .orderedAscending }
            : result.sorted(by: MatchDTO.byKickoffThenId)
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: V2Theme.Spacing.section) {
                filterCard
                results
            }
            .padding(.horizontal, V2Theme.Spacing.horizontal)
            .padding(.vertical, V2Theme.Spacing.section)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .v2DataRoomScene()
        .v2LoadingOverlay(store.isLoading, label: store.items.isEmpty ? "Loading matches…" : "Refreshing…")
        .safeAreaInset(edge: .top) {
            if let errorMessage = store.errorMessage, !store.items.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "wifi.slash")
                    Text("Refresh failed: \(errorMessage)").font(.caption).lineLimit(1)
                }
                .foregroundStyle(V2Theme.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial)
            }
        }
        .safeAreaInset(edge: .bottom) { footer }
        .v2FloatingHeader("Fixtures")
        .task(id: enabled.leagues.map(\.id)) {
            let validIds = Set(enabled.leagues.map(\.id))
            selectedLeagueIds.formIntersection(validIds)
            if selectedLeagueIds.isEmpty { selectedLeagueIds = validIds }
            await store.load(leagues: enabled.leagues)
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { tick in
            if store.isThrottled { store.now = tick }
        }
        .onChange(of: filterKey) { recomputeFiltered() }
        .task { recomputeFiltered() }
    }

    @ViewBuilder
    private var results: some View {
        if store.isLoading && store.items.isEmpty {
            Color.clear.frame(height: 200)
        } else if let errorMessage = store.errorMessage, store.items.isEmpty {
            ContentUnavailableView("Couldn't load matches", systemImage: "wifi.slash", description: Text(errorMessage))
        } else if filteredItems.isEmpty {
            ContentUnavailableView(
                "No matches",
                systemImage: "sportscourt",
                description: Text(store.items.isEmpty ? "No matches available right now." : "No matches match your filters.")
            )
        } else {
            VStack(spacing: 8) {
                ForEach(filteredItems) { item in
                    MatchRowV2(item: item, teamsById: store.teamsById)
                }
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 4) {
            if let lastRefreshed = store.lastRefreshed {
                Text("Updated \(lastRefreshed.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(V2Theme.textSecondary)
            }
            if store.isThrottled, let freshUntil = store.freshUntil {
                let remaining = Duration.seconds(max(0, freshUntil.timeIntervalSince(store.now)))
                Text("Refresh available in \(remaining.formatted(.time(pattern: .minuteSecond)))")
                    .font(.caption2)
                    .foregroundStyle(V2Theme.textSecondary)
            }
        }
        .padding(.bottom, 6)
        .background(.ultraThinMaterial)
    }

    // MARK: - Filter card

    @ViewBuilder
    private var filterCard: some View {
        Card(floating: true) {
            VStack(alignment: .leading, spacing: 14) {
                if enabled.leagues.count > 1 {
                    pillRow(title: "League") {
                        ForEach(enabled.leagues) { league in
                            let on = selectedLeagueIds.isEmpty || selectedLeagueIds.contains(league.id)
                            SelectablePill(title: league.displayName, isSelected: on) { toggleLeague(league.id) }
                        }
                    }
                }

                TextField("Search team", text: $teamQuery)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .padding(10)
                    .background(V2Theme.pillBackground, in: RoundedRectangle(cornerRadius: V2Theme.Radius.row, style: .continuous))

                pillRow(title: nil) {
                    SelectablePill(title: "All", isSelected: homeAway == .all) { homeAway = .all }
                    SelectablePill(title: "Home", isSelected: homeAway == .home) { homeAway = .home }
                    SelectablePill(title: "Away", isSelected: homeAway == .away) { homeAway = .away }
                }

                pillRow(title: nil) {
                    SelectablePill(title: "Kick-off", isSelected: !sortAZ) { sortAZ = false }
                    SelectablePill(title: "A–Z", isSelected: sortAZ) { sortAZ = true }
                }

                if !matchdays.isEmpty {
                    pillRow(title: "Matchday") {
                        SelectablePill(title: "All", isSelected: matchdayFilter == nil) { matchdayFilter = nil }
                        ForEach(matchdays, id: \.self) { md in
                            SelectablePill(title: "MD \(md)", isSelected: matchdayFilter == md) { matchdayFilter = md }
                        }
                    }
                }

                pillRow(title: nil) {
                    SelectablePill(title: "Dates", isSelected: dateRangeOn) {
                        withAnimation(.easeInOut(duration: 0.2)) { dateRangeOn.toggle() }
                    }
                }
                if dateRangeOn {
                    VStack(alignment: .leading, spacing: 8) {
                        DatePicker("From", selection: $dateFrom, displayedComponents: .date)
                        DatePicker("To", selection: $dateTo, in: dateFrom..., displayedComponents: .date)
                    }
                    .font(.subheadline)
                }

                HStack {
                    Spacer()
                    Button("Clear all", role: .destructive) { clearAll() }
                        .font(.caption.weight(.semibold))
                }
            }
        }
    }

    @ViewBuilder
    private func pillRow<Content: View>(title: String?, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                MicroLabel(text: title.uppercased())
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) { content() }
            }
        }
    }

    private func toggleLeague(_ id: String) {
        if selectedLeagueIds.contains(id) {
            if selectedLeagueIds.count > 1 { selectedLeagueIds.remove(id) }
        } else {
            selectedLeagueIds.insert(id)
        }
    }

    private func clearAll() {
        selectedLeagueIds = Set(enabled.leagues.map(\.id))
        teamQuery = ""
        homeAway = .all
        matchdayFilter = nil
        dateRangeOn = false
        sortAZ = false
    }
}

/// V2Theme-styled restyle of v1's `MatchRow` — same layout/tap-to-expand.
private struct MatchRowV2: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    let item: MatchDTO
    let teamsById: [Int: TeamDTO]
    @State private var expanded = false

    private var isPad: Bool { sizeClass == .regular }
    private var nameFont: Font { isPad ? .title3 : .body }
    private var scoreFont: Font { isPad ? .title3 : .subheadline }
    private var centreWidth: CGFloat { isPad ? 52 : 40 }

    private func shortName(_ id: Int) -> String { teamsById[id]?.shortName ?? teamsById[id]?.name ?? "Team \(id)" }
    private func fullName(_ id: Int) -> String { teamsById[id]?.name ?? "Team \(id)" }
    private func displayName(_ id: Int) -> String { expanded ? fullName(id) : shortName(id) }

    private var scoreText: String {
        if let h = item.homeScore, let a = item.awayScore { return "\(h)–\(a)" }
        return "v"
    }

    private var liveStatus: (text: String, color: Color)? {
        switch item.status {
        case "FINISHED":          return (AppString("FT"), V2Theme.textSecondary)
        case "IN_PLAY", "PAUSED": return (item.minute.map { "\($0)'" } ?? AppString("LIVE"), V2Theme.accent)
        case "POSTPONED":         return (AppString("Postp."), V2Theme.warning)
        default:                  return nil
        }
    }

    /// "Sat 23 Aug · 15:00" leading, "MD3" trailing — kickoff/matchday moved
    /// off the row into this header line so team names get the full row
    /// width instead of sharing it with a fixed trailing date column.
    @ViewBuilder
    private var scheduleLine: some View {
        let kickoff = FixtureFormat.kickoffDate(item.kickoff)
        if kickoff != nil || item.matchday != nil {
            HStack(spacing: 4) {
                if let kickoff {
                    Text(kickoff, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                    Text("·").foregroundStyle(V2Theme.textTertiary)
                    Text(kickoff, format: .dateTime.hour().minute())
                }
                Spacer(minLength: 8)
                if let md = item.matchday {
                    Text("MD \(md)")
                }
            }
            .font(.caption2)
            .foregroundStyle(V2Theme.textSecondary)
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            scheduleLine
            HStack(spacing: 8) {
                Text(displayName(item.homeTeamId)).font(nameFont).lineLimit(expanded ? nil : 1)
                    .foregroundStyle(V2Theme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 1) {
                    Text(scoreText).font(scoreFont).bold().monospacedDigit()
                        .foregroundStyle(V2Theme.textPrimary)
                    if let live = liveStatus {
                        Text(live.text).font(.caption2).foregroundStyle(live.color).lineLimit(1)
                    }
                }
                .frame(width: centreWidth)

                Text(displayName(item.awayTeamId)).font(nameFont).lineLimit(expanded ? nil : 1)
                    .foregroundStyle(V2Theme.textPrimary)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .v2FloatingCard(cornerRadius: V2Theme.Radius.row)
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() } }
    }
}
