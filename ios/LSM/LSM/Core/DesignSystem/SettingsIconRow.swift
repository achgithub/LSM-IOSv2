import SwiftUI

/// Colored rounded-square icon badge, matching the visual language of Apple's
/// own Settings app — used so the top-level Settings list reads as a set of
/// scannable destinations rather than a wall of text.
struct SettingsIcon: View {
    let systemName: String
    let color: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(color.gradient)
            .frame(width: 29, height: 29)
            .overlay {
                Image(systemName: systemName)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)
            }
    }
}

/// A top-level Settings row — icon, title, and an optional trailing value
/// preview (e.g. the current plan or language) — for use as a
/// `NavigationLink` label.
struct SettingsRow: View {
    let systemName: String
    let color: Color
    let title: LocalizedStringKey
    var value: String?

    var body: some View {
        HStack(spacing: 12) {
            SettingsIcon(systemName: systemName, color: color)
            Text(title)
            Spacer()
            if let value {
                Text(value).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}
