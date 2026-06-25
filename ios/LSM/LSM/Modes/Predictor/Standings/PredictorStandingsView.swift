import SwiftUI

/// On-device Predictor league table — standard competition ranking ("1, 1,
/// 3"), ties alphabetical, per §0. Local aggregation only, no cloud. Row
/// styling borrowed from `Shared/Standings/StandingsView`'s `StandingRow`
/// (that view itself is coupled to the Worker's `StandingDTO`/`LeagueDataCache`,
/// so it isn't reused directly here).
struct PredictorStandingsView: View {
    let game: Game

    private var rows: [PredictorStandingRow] { PredictorStandings.rows(for: game) }

    var body: some View {
        Group {
            if rows.isEmpty {
                ContentUnavailableView("No players yet", systemImage: "person.3")
            } else {
                List(rows) { row in
                    PredictorStandingRowView(row: row)
                }
            }
        }
        .navigationTitle("Standings")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PredictorStandingRowView: View {
    let row: PredictorStandingRow

    var body: some View {
        HStack(spacing: 12) {
            Text("\(row.position)")
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(width: 28, alignment: .leading)
                .foregroundStyle(.secondary)
            Text(row.player.name).lineLimit(1)
            Spacer()
            Text("\(row.points)")
                .bold()
                .frame(width: 32, alignment: .trailing)
                .monospacedDigit()
        }
    }
}
