import SwiftUI

/// One league-table row as its own card: rank, team name, P/W metadata,
/// win-percentage in the accent color.
struct StandingsCard: View {
    let rank: Int
    let name: String
    let played: Int
    let won: Int
    let winPercentage: Int

    var body: some View {
        Card(padding: 16) {
            HStack(spacing: 14) {
                Text("\(rank)")
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(minWidth: 28, alignment: .leading)
                    .foregroundStyle(V2Theme.textSecondary)
                Text(name)
                    .font(V2Theme.Typography.rowTitle)
                    .foregroundStyle(V2Theme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text("P\(played)")
                    .font(V2Theme.Typography.metadata)
                    .foregroundStyle(V2Theme.textSecondary)
                Text("W\(won)")
                    .font(V2Theme.Typography.metadata)
                    .foregroundStyle(V2Theme.textSecondary)
                Text("\(winPercentage)%")
                    .font(.body.weight(.bold))
                    .foregroundStyle(V2Theme.accent)
                    .frame(minWidth: 44, alignment: .trailing)
            }
        }
    }
}
