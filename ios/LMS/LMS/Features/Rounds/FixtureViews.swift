import SwiftUI

enum FixtureFormat {
    static let iso = ISO8601DateFormatter()
    static func kickoffDate(_ string: String) -> Date? { iso.date(from: string) }
}

/// Compact fixture row: home tile/TLA · v · away TLA/tile, with the kick-off
/// date + time and matchday stacked on the trailing edge (info only).
struct FixtureLabel: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    let fixture: FixtureDTO
    let teamsById: [Int: TeamDTO]

    private var isPad: Bool { sizeClass == .regular }
    private var tileSize: TileSize { isPad ? .medium : .small }
    private var codeFont: Font { isPad ? .body.weight(.semibold) : .caption.weight(.semibold) }
    private var codeWidth: CGFloat { isPad ? 48 : 36 }

    private func tla(_ id: Int) -> String { teamsById[id]?.tla ?? "\(id)" }
    private var kickoff: Date? { FixtureFormat.kickoffDate(fixture.kickoff) }

    var body: some View {
        HStack(spacing: 8) {
            TeamTile(tla: teamsById[fixture.homeTeamId]?.tla, size: tileSize)
            Text(tla(fixture.homeTeamId)).font(codeFont).frame(width: codeWidth, alignment: .leading)
            Text("v").font(.caption2).foregroundStyle(.secondary)
            Text(tla(fixture.awayTeamId)).font(codeFont).frame(width: codeWidth, alignment: .leading)
            TeamTile(tla: teamsById[fixture.awayTeamId]?.tla, size: tileSize)
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                if let kickoff {
                    Text(kickoff, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                        .font(.caption2).foregroundStyle(.secondary)
                    Text(kickoff, format: .dateTime.hour().minute())
                        .font(.caption2.weight(.semibold))
                }
                if let matchday = fixture.matchday {
                    Text("MD \(matchday)").font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
    }
}
