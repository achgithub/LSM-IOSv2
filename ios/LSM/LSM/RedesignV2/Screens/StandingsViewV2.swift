import SwiftUI

/// Card-based restyle of `StandingsView`, sharing the same `StandingsStore`
/// (load/refresh/throttle logic) so both stay correct in parallel. Reached
/// only from the V2 preview menu — the original `StandingsView` in the real
/// tab bar is untouched.
struct StandingsViewV2: View {
    @Environment(EnabledLeagues.self) private var enabled
    @State private var selectedLeague: LeagueOption?
    @State private var store = StandingsStore()

    private var league: LeagueOption { selectedLeague ?? enabled.leagues.first ?? Leagues.home }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                if enabled.leagues.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(enabled.leagues) { option in
                                SelectablePill(title: option.displayName, isSelected: option.id == league.id) {
                                    selectedLeague = option
                                }
                            }
                        }
                    }
                }
                if store.isLoading && store.standings.isEmpty {
                    ProgressView("Loading standings…")
                        .padding(.top, 60)
                } else if let errorMessage = store.errorMessage, store.standings.isEmpty {
                    ContentUnavailableView(
                        "Couldn't load standings",
                        systemImage: "wifi.slash",
                        description: Text(errorMessage)
                    )
                    .padding(.top, 40)
                } else {
                    ForEach(store.standings) { row in
                        let team = store.teamsById[row.teamId]
                        StandingsCard(
                            rank: row.position,
                            name: team?.shortName ?? team?.name ?? "Team \(row.teamId)",
                            played: row.played,
                            won: row.won,
                            winPercentage: row.played > 0 ? Int((Double(row.won) / Double(row.played) * 100).rounded()) : 0
                        )
                    }
                }
            }
            .padding(.horizontal, V2Theme.Spacing.horizontal)
            .padding(.vertical, V2Theme.Spacing.section)
        }
        .background(V2Theme.background.ignoresSafeArea())
        .v2Header("Standings")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { store.refresh(league: league) } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Refresh")
                .disabled(store.isLoading || store.isThrottled)
            }
        }
        .task(id: league) { await store.load(league: league, force: false) }
        .task(id: store.freshUntil) { await store.armClock() }
    }
}
