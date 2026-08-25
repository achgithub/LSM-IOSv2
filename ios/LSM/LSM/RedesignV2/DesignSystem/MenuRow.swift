import SwiftUI

/// Drill-down menu row: leading icon, title, optional trailing value, and a
/// chevron — each instance its own Card, stacked with spacing rather than
/// packed into one List (matches the "Core Data" portal-menu reference).
/// Use inside a `NavigationLink` label for a tappable row.
struct MenuRow: View {
    let systemImage: String
    let title: String
    var value: String?
    /// Icon color — defaults to the shared accent, but pass a mode's own
    /// color (`V2Theme.Mode.color(for:)`) when the row represents that mode,
    /// so it reads consistently with how the mode is colored elsewhere
    /// (e.g. the games portal's section headers).
    var tint: Color = V2Theme.accent
    /// See `Card.floating` — pass true on a screen with a photo background.
    var floating: Bool = false

    var body: some View {
        Card(padding: 16, floating: floating) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(tint)
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
