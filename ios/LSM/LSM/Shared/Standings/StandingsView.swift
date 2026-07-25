import SwiftUI

/// League table from the Worker, with §15 team tiles. Browsing is a free live
/// read; the explicit refresh button is the free-tier rewarded-ad gate (matches
/// Scores), and shows when the data was last refreshed.
struct StandingsView: View {
    @Environment(EnabledLeagues.self) private var enabled
    @State private var selectedLeague: LeagueOption?
    @State private var store = StandingsStore()

    private var league: LeagueOption { selectedLeague ?? enabled.leagues.first ?? Leagues.home }
    private var leagueBinding: Binding<LeagueOption> {
        Binding(get: { league }, set: { selectedLeague = $0 })
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.isLoading && store.standings.isEmpty {
                    ProgressView("Loading standings…")
                } else if let errorMessage = store.errorMessage, store.standings.isEmpty {
                    ContentUnavailableView(
                        "Couldn't load standings",
                        systemImage: "wifi.slash",
                        description: Text(errorMessage)
                    )
                } else {
                    List(store.standings) { row in
                        StandingRow(row: row, team: store.teamsById[row.teamId])
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
                    Button { store.refresh(league: league) } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Refresh")
                    .disabled(store.isLoading || store.isThrottled)
                }
            }
            // Reloads when the chosen league changes (browsing, so not ad-gated —
            // the explicit refresh button is the gated fetch action).
            .task(id: league) { await store.load(league: league, force: false) }
            // One-shot: wake exactly when the throttle lapses to flip the button
            // back on (and immediately if it already has, e.g. on tab re-entry).
            .task(id: store.freshUntil) { await store.armClock() }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 4) {
                    if let lastRefreshed = store.lastRefreshed {
                        Text("Updated \(lastRefreshed.formatted(date: .omitted, time: .shortened))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if store.isThrottled, let freshUntil = store.freshUntil {
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
