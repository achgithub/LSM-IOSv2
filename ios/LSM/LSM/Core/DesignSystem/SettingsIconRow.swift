import SwiftUI

/// Rounded-square icon badge for a top-level Settings row, in the app's one
/// brand blue (see `Brand.sharedBlue`) rather than Apple's per-row rainbow —
/// this app reserves color for status (green/orange/red), so every tile
/// shares a single accent instead of a different color each.
struct SettingsIcon: View {
    let systemName: String

    var body: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(Brand.sharedBlue.gradient)
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
    let title: LocalizedStringKey
    var value: String?

    var body: some View {
        HStack(spacing: 12) {
            SettingsIcon(systemName: systemName)
            Text(title)
            Spacer()
            if let value {
                Text(value).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}
