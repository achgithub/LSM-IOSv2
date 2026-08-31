import SwiftUI

/// Column widths shared between `StandingsHeaderRow` and each
/// `StandingsCard` row so the two stay pixel-aligned.
private enum StandingsColumn {
    static let stat: CGFloat = 14
    static let goalDifference: CGFloat = 26
    static let points: CGFloat = 24
}

/// Header row (P W D L GD PTS) — place once above the list of `StandingsCard`
/// rows.
struct StandingsHeaderRow: View {
    var body: some View {
        // Same spacing as StandingsCard's row below — must match for the
        // P/W/D/L/GD/PTS columns to stay aligned.
        HStack(spacing: 6) {
            Spacer()
            label("P")
            label("W")
            label("D")
            label("L")
            label("GD", width: StandingsColumn.goalDifference)
            label("PTS", width: StandingsColumn.points)
        }
        .padding(.horizontal, 16)
    }

    private func label(_ text: String, width: CGFloat = StandingsColumn.stat) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .foregroundStyle(V2Theme.textTertiary)
            .frame(minWidth: width, alignment: .trailing)
    }
}

/// One league-table row as its own card: rank, team name, then the full
/// P/W/D/L/GD/PTS line every standard league table shows.
struct StandingsCard: View {
    let rank: Int
    let name: String
    let played: Int
    let won: Int
    let drawn: Int
    let lost: Int
    let goalDifference: Int
    let points: Int
    /// See `Card.floating` — pass true on a screen with a photo background.
    var floating: Bool = false

    private var goalDifferenceText: String {
        goalDifference > 0 ? "+\(goalDifference)" : "\(goalDifference)"
    }

    var body: some View {
        Card(padding: 16, floating: floating) {
            // Spacing/column widths tightened from the original 10/18/32/30
            // — the name was chopping too aggressively (e.g. "Wolverhampton
            // Wanderers") with six stat columns eating most of the row.
            HStack(spacing: 6) {
                Text("\(rank)")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(minWidth: 18, alignment: .leading)
                    .foregroundStyle(V2Theme.textSecondary)
                Text(name)
                    .font(V2Theme.Typography.rowTitle)
                    .foregroundStyle(V2Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)
                stat(played)
                stat(won)
                stat(drawn)
                stat(lost)
                Text(goalDifferenceText)
                    .font(V2Theme.Typography.metadata.monospacedDigit())
                    .foregroundStyle(V2Theme.textSecondary)
                    .frame(minWidth: StandingsColumn.goalDifference, alignment: .trailing)
                Text("\(points)")
                    .font(.body.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(V2Theme.accent)
                    .frame(minWidth: StandingsColumn.points, alignment: .trailing)
            }
        }
    }

    private func stat(_ value: Int) -> some View {
        Text("\(value)")
            .font(V2Theme.Typography.metadata.monospacedDigit())
            .foregroundStyle(V2Theme.textSecondary)
            .frame(minWidth: StandingsColumn.stat, alignment: .trailing)
    }
}
