import SwiftUI

/// League table from the Worker, with §15 team tiles. Live read; subscriber
/// auto-refresh and the free-tier ad gate come in later phases.
struct StandingsView: View {
    @Environment(EnabledLeagues.self) private var enabled
    @State private var selectedLeague: LeagueOption?
    @State private var standings: [StandingDTO] = []
    @State private var teamsById: [Int: TeamDTO] = [:]
    @State private var isLoading = false
    @State private var errorMessage: String?

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
            .navigationTitle("Standings")
            .toolbar {
                if enabled.leagues.count > 1 {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Picker("League", selection: leagueBinding) {
                                ForEach(enabled.leagues) { Text($0.name).tag($0) }
                            }
                        } label: {
                            Label(league.shortName, systemImage: "trophy")
                        }
                    }
                } else {
                    ToolbarItem(placement: .principal) {
                        Text(league.name).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    }
                }
            }
            // Reloads when the chosen league changes.
            .task(id: league) { await load() }
            .refreshable { await load() }
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        let client = league.client
        do {
            async let standingsReq = client.standings()
            async let teamsReq = client.teams()
            let (standings, teams) = try await (standingsReq, teamsReq)
            self.standings = standings
            self.teamsById = Dictionary(teams.map { ($0.externalId, $0) }, uniquingKeysWith: { first, _ in first })
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

private struct StandingRow: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    let row: StandingDTO
    let team: TeamDTO?

    private var isPad: Bool { sizeClass == .regular }
    private var nameFont: Font { isPad ? .title3 : .body }

    var body: some View {
        HStack(spacing: isPad ? 16 : 12) {
            Text("\(row.position)")
                .font(nameFont)
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(width: isPad ? 40 : 28, alignment: .leading)
                .foregroundStyle(.secondary)
            Text(team?.shortName ?? team?.name ?? "Team \(row.teamId)")
                .font(nameFont)
                .lineLimit(1)
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
        .padding(.vertical, isPad ? 6 : 0)
    }

    private func stat(_ label: String, _ value: Int) -> some View {
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
