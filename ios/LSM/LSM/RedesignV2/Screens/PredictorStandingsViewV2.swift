import SwiftUI

/// Card restyle of `PredictorStandingsView` — same `PredictorStandings.rows`
/// aggregation, ranked rows as cards instead of a `List`.
struct PredictorStandingsViewV2: View {
    let game: Game

    private var rows: [PredictorStandingRow] { PredictorStandings.rows(for: game) }

    var body: some View {
        NavigationStack {
            Group {
                if rows.isEmpty {
                    ContentUnavailableView("No players yet", systemImage: "person.3")
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(rows) { row in
                                PredictorStandingRowV2(row: row)
                            }
                        }
                        .padding(.horizontal, V2Theme.Spacing.horizontal)
                        .padding(.vertical, V2Theme.Spacing.section)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .v2PredictorFormScene()
            .v2FloatingHeader("Standings")
        }
    }
}

private struct PredictorStandingRowV2: View {
    let row: PredictorStandingRow

    var body: some View {
        Card(padding: 16, floating: true) {
            HStack(spacing: 14) {
                Text("\(row.position)")
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(minWidth: 28, alignment: .leading)
                    .foregroundStyle(V2Theme.textSecondary)
                Text(row.player.name)
                    .font(V2Theme.Typography.rowTitle)
                    .foregroundStyle(V2Theme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text("\(row.points)")
                    .font(.body.weight(.bold).monospacedDigit())
                    .foregroundStyle(V2Theme.Mode.predictor)
                    .frame(minWidth: 32, alignment: .trailing)
            }
        }
    }
}
