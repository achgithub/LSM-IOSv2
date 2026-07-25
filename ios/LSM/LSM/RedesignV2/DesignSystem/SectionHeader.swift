import SwiftUI

/// Bold section heading with an optional secondary subtitle, used above a
/// group of cards instead of a List section header.
struct SectionHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(V2Theme.Typography.sectionHeading)
                .foregroundStyle(V2Theme.textPrimary)
            if let subtitle {
                Text(subtitle)
                    .font(V2Theme.Typography.metadata)
                    .foregroundStyle(V2Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
