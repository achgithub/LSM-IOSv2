import SwiftUI

/// Drill-down menu row: leading icon, title, optional trailing value, and a
/// chevron — each instance its own Card, stacked with spacing rather than
/// packed into one List (matches the "Core Data" portal-menu reference).
/// Use inside a `NavigationLink` label for a tappable row.
struct MenuRow: View {
    let systemImage: String
    let title: String
    var value: String?

    var body: some View {
        Card(padding: 16) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(V2Theme.accent)
                    .frame(width: 22)
                Text(title)
                    .font(V2Theme.Typography.rowTitle)
                    .foregroundStyle(V2Theme.textPrimary)
                Spacer(minLength: 8)
                if let value {
                    Text(value)
                        .font(V2Theme.Typography.metadata)
                        .foregroundStyle(V2Theme.textSecondary)
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(V2Theme.textSecondary)
            }
        }
    }
}
