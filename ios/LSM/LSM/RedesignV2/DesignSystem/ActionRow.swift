import SwiftUI

/// Plain tappable row for actions stacked inside a shared `Card` (e.g. a
/// round's "Enter Picks" / "Edit Fixtures" / share rows) — distinct from
/// `MenuRow`, which wraps each row in its own `Card` for top-level
/// navigation menus. `isEnabled: false` dims and disables the row so
/// callers stop having to hand-manage tint/opacity together.
struct ActionRow: View {
    /// `LocalizedStringKey` so literals go through the catalog — as `String`
    /// this rendered English in every language (see CLAUDE.md).
    let title: LocalizedStringKey
    let icon: String
    var tint: Color = V2Theme.accent
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: icon)
                Spacer()
                Image(systemName: "chevron.right").font(.caption)
            }
        }
        .foregroundStyle(tint)
        .opacity(isEnabled ? 1 : 0.4)
        .disabled(!isEnabled)
    }
}
