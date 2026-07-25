import SwiftUI

/// Full-width gold rounded button — the V2 replacement for the default
/// bordered/plain Button styles on primary actions ("Save", "Add").
struct PrimaryButton: View {
    let title: String
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.body.weight(.bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .foregroundStyle(V2Theme.accentOnAccent)
        .background(V2Theme.accent, in: RoundedRectangle(cornerRadius: V2Theme.Radius.button, style: .continuous))
        .opacity(isEnabled ? 1 : 0.4)
        .disabled(!isEnabled)
    }
}

/// Compact pill toggle used for exclusive-choice rows ("Who? Ellie Reyes /
/// Ryan Blackwood") — filled gold when selected, outlined otherwise.
struct SelectablePill: View {
    let title: String
    let isSelected: Bool
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
                .fill(isSelected ? V2Theme.accent : V2Theme.pillBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: V2Theme.Radius.pill, style: .continuous)
                .strokeBorder(isSelected ? .clear : V2Theme.cardBorder, lineWidth: 1)
        )
    }
}
