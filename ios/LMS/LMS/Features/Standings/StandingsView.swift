import SwiftUI

/// League table from the Worker, with §15 team tiles. Live read; subscriber
/// auto-refresh and the free-tier ad gate come in later phases.
struct StandingsView: View {
    @State private var standings: [StandingDTO] = []
    @State private var teamsById: [Int: TeamDTO] = [:]
    @State private var isLoading = false
    @State private var errorMessage: String?

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
            .task { await load() }
            .refreshable { await load() }
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            async let standingsReq = APIClient.shared.standings()
            async let teamsReq = APIClient.shared.teams()
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
    let row: StandingDTO
    let team: TeamDTO?

    var body: some View {
        HStack(spacing: 12) {
            Text("\(row.position)")
                .frame(width: 22, alignment: .leading)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            TeamTile(tla: team?.tla, size: .small)
            Text(team?.shortName ?? team?.name ?? "Team \(row.teamId)")
                .lineLimit(1)
            Spacer()
            Text("\(row.played)·\(row.won)·\(row.drawn)·\(row.lost)")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Text("\(row.points)")
                .bold()
                .frame(width: 32, alignment: .trailing)
                .monospacedDigit()
        }
    }
}
