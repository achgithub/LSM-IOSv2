import SwiftUI

/// V2 restyle of `FixtureLabel` — moves kickoff date/time and matchday off
/// the row into a header line above the team names (matching `MatchesViewV2`'s
/// `MatchRowV2` pattern — see its doc comment), so team names get the full
/// row width instead of sharing it with a fixed-width trailing date column.
/// Same `(fixture:teamsById:)` signature as `FixtureLabel`, so it drops into
/// every V2 fixture-row usage (Open Round, Results Entry, Predictions Entry)
/// without touching the V1 screens that still use `FixtureLabel` unchanged.
struct FixtureLabelV2: View {
    let fixture: MatchDTO
    let teamsById: [Int: TeamDTO]

    private func name(_ id: Int) -> String {
        teamsById[id]?.shortName ?? teamsById[id]?.name ?? "Team \(id)"
    }
    private var kickoff: Date? { FixtureFormat.kickoffDate(fixture.kickoff) }

    @ViewBuilder
    private var scheduleLine: some View {
        if kickoff != nil || fixture.matchday != nil {
            HStack(spacing: 4) {
                if let kickoff {
                    Text(kickoff, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                    Text("·").foregroundStyle(V2Theme.textTertiary)
                    Text(kickoff, format: .dateTime.hour().minute())
                }
                Spacer(minLength: 8)
                if let matchday = fixture.matchday {
                    Text("MD \(matchday)")
                }
            }
            .font(.caption2)
            .foregroundStyle(V2Theme.textSecondary)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            scheduleLine
            HStack(spacing: 8) {
                Text(name(fixture.homeTeamId)).lineLimit(1).minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                Text("v").font(.caption2).foregroundStyle(V2Theme.textTertiary)
                Text(name(fixture.awayTeamId)).lineLimit(1).minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.callout)
        }
    }
}
