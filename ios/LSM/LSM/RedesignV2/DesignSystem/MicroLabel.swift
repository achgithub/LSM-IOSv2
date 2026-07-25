import SwiftUI

/// Small uppercase-tracked label ("ROUND 14", "LEAGUE STANDINGS") used above
/// a section's content, optionally with a leading icon.
struct MicroLabel: View {
    var systemImage: String?
    let text: String
    var tint: Color = V2Theme.textSecondary

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 11))
            }
            Text(text)
                .font(V2Theme.Typography.microLabel)
                .textCase(.uppercase)
                .tracking(1.1)
        }
        .foregroundStyle(tint)
    }
}
