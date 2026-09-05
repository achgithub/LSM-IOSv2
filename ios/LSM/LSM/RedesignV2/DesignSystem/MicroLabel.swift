import SwiftUI

/// Small uppercase-tracked label ("ROUND 14", "LEAGUE STANDINGS") used above
/// a section's content, optionally with a leading icon.
struct MicroLabel: View {
    var systemImage: String?
    private let text: Text
    var tint: Color = V2Theme.textSecondary

    /// UI copy — goes through `Localizable.xcstrings`.
    init(systemImage: String? = nil, text: LocalizedStringKey, tint: Color = V2Theme.textSecondary) {
        self.systemImage = systemImage
        self.text = Text(text)
        self.tint = tint
    }

    /// For a mode/league display name already localized at its source.
    init(systemImage: String? = nil, verbatim text: String, tint: Color = V2Theme.textSecondary) {
        self.systemImage = systemImage
        self.text = Text(verbatim: text)
        self.tint = tint
    }

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 11))
            }
            text
                .font(V2Theme.Typography.microLabel)
                .textCase(.uppercase)
                .tracking(1.1)
        }
        .foregroundStyle(tint)
    }
}
