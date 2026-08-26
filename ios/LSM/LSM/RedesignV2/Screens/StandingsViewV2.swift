import SwiftUI

/// Card-based restyle of `StandingsView`, sharing the same `StandingsStore`
/// (load/refresh/throttle logic) so both stay correct in parallel. The
/// original `StandingsView` in the real tab bar is untouched. Embedded
/// inline inside `LeaguesPortalViewV2`'s Standings accordion panel, not a
/// pushed screen — no scene/header of its own; the portal supplies both.
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
                    Color.clear.frame(height: 200)
                } else if let errorMessage = store.errorMessage, store.standings.isEmpty {
                    ContentUnavailableView(
                        "Couldn't load standings",
                        systemImage: "wifi.slash",
                        description: Text(errorMessage)
                    )
                    .padding(.top, 40)
                } else {
                    StandingsHeaderRow()
                    ForEach(store.standings) { row in
                        let team = store.teamsById[row.teamId]
                        StandingsCard(
                            rank: row.position,
                            name: team?.shortName ?? team?.name ?? "Team \(row.teamId)",
                            played: row.played,
                            won: row.won,
                            drawn: row.drawn,
                            lost: row.lost,
                            goalDifference: row.goalDifference,
                            points: row.points,
                            floating: true
                        )
                    }
                }
            }
            .padding(.horizontal, V2Theme.Spacing.horizontal)
            .padding(.vertical, V2Theme.Spacing.section)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .v2LoadingOverlay(store.isLoading, label: store.standings.isEmpty ? "Loading standings…" : "Refreshing…")
        .task(id: league) { await store.load(league: league, force: false) }
        .task(id: store.freshUntil) { await store.armClock() }
    }
}
