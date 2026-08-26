import SwiftUI

/// Full-width rounded button, filled `V2Theme.accent` by default — the V2
/// replacement for the default bordered/plain Button styles on primary
/// actions ("Save", "Add"). Pass `tint:` for a mode-specific fill.
struct PrimaryButton: View {
    let title: String
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
    let title: String
    let isSelected: Bool
    /// Fill color when selected — defaults to the shared accent; pass a
    /// mode's own color on a mode-specific screen to match that mode's
    /// identity elsewhere.
    var tint: Color = V2Theme.accent
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
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
