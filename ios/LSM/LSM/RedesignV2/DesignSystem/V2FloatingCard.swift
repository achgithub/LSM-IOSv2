import SwiftUI

extension View {
    /// Floating card treatment used across the stadium/team-room scenes —
    /// so every panel over a photo background reads as one consistent
    /// system instead of each screen inventing its own (originally
    /// hand-rolled per-view in `GameSummaryRow`; factored out once
    /// `PlayersViewV2` needed the same look).
    ///
    /// Nearly-opaque fill, not `.thinMaterial` — a translucent blur let too
    /// much photo detail through and made cards read as a muddy grey
    /// surface competing with the background instead of sitting clearly
    /// above it. A cool-blue-tinted shadow (not plain black) and a
    /// restrained border, not a bright white outline. Caller applies its
    /// own padding first, same as any `.background`.
    func v2FloatingCard(cornerRadius: CGFloat = V2Theme.Radius.card) -> some View {
        self
            .background(V2Theme.cardBackground.opacity(0.96), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).stroke(V2Theme.cardBorder.opacity(0.7)))
            .shadow(color: Color(red: 0.20, green: 0.27, blue: 0.36).opacity(0.16), radius: 12, y: 5)
    }
}
