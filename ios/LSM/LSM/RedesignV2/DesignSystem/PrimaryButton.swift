import SwiftUI

/// Full-width rounded button, filled `V2Theme.accent` by default — the V2
/// replacement for the default bordered/plain Button styles on primary
/// actions ("Save", "Add"). Pass `tint:` for a mode-specific fill.
///
/// `title` is `LocalizedStringKey` so a literal goes through
/// `Localizable.xcstrings` automatically — as `String` it hit `Text`'s
/// verbatim initializer and rendered English in every language. A button
/// label is always UI copy, never user data, so there's deliberately no
/// verbatim escape here.
struct PrimaryButton: View {
    let title: LocalizedStringKey
    var isEnabled = true
    /// Fill color — defaults to the shared accent; pass a mode's own color
    /// (`V2Theme.Mode.color(for:)`) on a mode-specific screen (e.g. a
    /// mode's "Create Game") so it matches that mode's identity elsewhere.
    var tint: Color = V2Theme.accent
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.body.weight(.bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .foregroundStyle(V2Theme.accentOnAccent)
        .background(tint, in: RoundedRectangle(cornerRadius: V2Theme.Radius.button, style: .continuous))
        .opacity(isEnabled ? 1 : 0.4)
        .disabled(!isEnabled)
    }
}

/// Compact pill toggle used for exclusive-choice rows ("Who? Ellie Reyes /
/// Ryan Blackwood") — filled gold when selected, outlined otherwise.
struct SelectablePill: View {
    private let title: Text
    let isSelected: Bool
    /// Fill color when selected — defaults to the shared accent; pass a
    /// mode's own color on a mode-specific screen to match that mode's
    /// identity elsewhere.
    var tint: Color = V2Theme.accent
    let action: () -> Void

    /// UI copy — goes through `Localizable.xcstrings`.
    init(title: LocalizedStringKey, isSelected: Bool, tint: Color = V2Theme.accent, action: @escaping () -> Void) {
        self.title = Text(title)
        self.isSelected = isSelected
        self.tint = tint
        self.action = action
    }

    /// For a player/league/group name, or a string already localized by its
    /// own `label`/`displayName` (see `Enums.swift`) — never re-looked-up.
    init(verbatim title: String, isSelected: Bool, tint: Color = V2Theme.accent, action: @escaping () -> Void) {
        self.title = Text(verbatim: title)
        self.isSelected = isSelected
        self.tint = tint
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            title
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
        .foregroundStyle(isSelected ? V2Theme.accentOnAccent : V2Theme.textPrimary)
        .background(
            RoundedRectangle(cornerRadius: V2Theme.Radius.pill, style: .continuous)
                .fill(isSelected ? tint : V2Theme.pillBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: V2Theme.Radius.pill, style: .continuous)
                .strokeBorder(isSelected ? .clear : V2Theme.cardBorder, lineWidth: 1)
        )
    }
}
