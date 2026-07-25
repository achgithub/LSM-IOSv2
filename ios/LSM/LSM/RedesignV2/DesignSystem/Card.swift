import SwiftUI

/// Base card container for V2 screens — flat panel fill, no border by
/// default (matching the reference mockup's borderless cards on a navy
/// background). Set `isHighlighted` for a selected/active row: tinted
/// background + accent border, like the picked fixture in the reference.
struct Card<Content: View>: View {
    var padding: CGFloat = V2Theme.Spacing.cardPadding
    var isHighlighted: Bool = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isHighlighted ? V2Theme.highlightBackground : V2Theme.cardBackground,
                in: RoundedRectangle(cornerRadius: V2Theme.Radius.card, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: V2Theme.Radius.card, style: .continuous)
                    .strokeBorder(isHighlighted ? V2Theme.accent : V2Theme.cardBorder, lineWidth: isHighlighted ? 1.5 : 1)
            )
    }
}
