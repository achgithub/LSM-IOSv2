import SwiftUI

/// Floating header for a full-bleed photo scene — back chevron (omit for a
/// stack root, e.g. Home) + title, no enclosing bar, so the photo shows
/// through behind it. Replaces `.v2Header` on screens using
/// `.v2StadiumScene()`/`.v2TrophyRoomScene()`/etc., which need
/// `.toolbar(.hidden, for: .navigationBar)` + this instead of a real nav
/// bar — see `V2StadiumBackdrop`'s and `PlayersViewV2`'s doc comments for
/// why a real nav bar (even with a hidden background) still clips the photo
/// under the status bar. Factored out after that header was hand-rolled
/// separately on Home and Players — don't hand-roll a third copy.
struct V2FloatingHeader<Trailing: View, Tiles: View>: View {
    let title: String
    var showBack: Bool = true
    /// Taller when `tiles` is non-empty (the scrim needs to cover the tile
    /// grid too, not just the title row) — set by the `Tiles == EmptyView`
    /// vs. two-generic initializers below, not passed directly.
    var scrimHeight: CGFloat = 160
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var tiles: () -> Tiles
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .top) {
            // A plain sky (Home) has enough natural contrast for
            // free-floating text; the interior photos (Trophy/Team/Data
            // Room, Tactics Office) are busier and don't. This scrim uses
            // `V2Theme.background` itself (light in light mode, dark in
            // dark mode) rather than a fixed tint, so it lightens the busy
            // photo behind light-mode's dark text and darkens it behind
            // dark-mode's light text — right contrast direction either way.
            // Explicit `ZStack`, not `.background()` — a background view
            // sized larger than its foreground is unreliable to position
            // predictably when the foreground sits inside a
            // `.safeAreaInset` closure.
            //
            // Plain two-stop fade, not several uneven opacity steps — with
            // uneven-sized jumps between stops, the gradient's rate of
            // change visibly bends partway down over a flat/uniform part of
            // a photo (ceilings especially), reading as a hard seam/line
            // instead of a smooth wash. `.ignoresSafeArea` so the tint
            // starts above the status bar, not right at its lower edge —
            // that boundary was the other seam.
            LinearGradient(
                colors: [V2Theme.background.opacity(0.6), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: scrimHeight)
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)

            VStack(spacing: 12) {
                // A plain leading/trailing HStack pushed the title off-center
                // whenever one side was empty (e.g. no back button) or the
                // two sides carried different widths — title centers
                // absolutely here, with back/trailing floating over it in
                // their natural corners instead of sharing its layout.
                ZStack {
                    Text(title)
                        .font(V2Theme.Typography.pageTitle)
                        .foregroundStyle(V2Theme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .center)
                    HStack {
                        if showBack {
                            Button {
                                dismiss()
                            } label: {
                                Image(systemName: "chevron.left")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(V2Theme.textPrimary)
                                    .frame(width: 36, height: 36)
                                    .background(V2Theme.cardBackground, in: Circle())
                            }
                            .accessibilityLabel("Back")
                        }
                        Spacer()
                        trailing()
                    }
                }
                tiles()
            }
            .padding(.horizontal, V2Theme.Spacing.horizontal)
            .padding(.top, 10)
            .padding(.bottom, 14)
        }
    }
}

extension V2FloatingHeader where Trailing == EmptyView, Tiles == EmptyView {
    init(title: String, showBack: Bool = true) {
        self.title = title
        self.showBack = showBack
        self.trailing = { EmptyView() }
        self.tiles = { EmptyView() }
    }
}

extension V2FloatingHeader where Tiles == EmptyView {
    init(title: String, showBack: Bool = true, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.showBack = showBack
        self.trailing = trailing
        self.tiles = { EmptyView() }
    }
}

extension V2FloatingHeader where Trailing == EmptyView {
    init(title: String, showBack: Bool = true, scrimHeight: CGFloat = 260, @ViewBuilder tiles: @escaping () -> Tiles) {
        self.title = title
        self.showBack = showBack
        self.scrimHeight = scrimHeight
        self.trailing = { EmptyView() }
        self.tiles = tiles
    }
}

extension View {
    /// Applies `.toolbar(.hidden, for: .navigationBar)` and reserves the
    /// header's space via `.safeAreaInset(edge: .top)` — pair with a
    /// `.v2*Scene()` background modifier, not `.v2Header`.
    func v2FloatingHeader<Trailing: View>(
        _ title: String,
        showBack: Bool = true,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) -> some View {
        self
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top) {
                V2FloatingHeader(title: title, showBack: showBack, trailing: trailing)
            }
    }

    func v2FloatingHeader(_ title: String, showBack: Bool = true) -> some View {
        v2FloatingHeader(title, showBack: showBack) { EmptyView() }
    }

    /// Header + a `V2TileGrid` (see that type) appended below the title
    /// row, both inside the same scrim — for screens whose actions/stats
    /// moved from standalone header icons into the shared tile system
    /// (currently `GamesPortalViewV2`/`PlayersViewV2`). Distinct name from
    /// `v2FloatingHeader(_:trailing:)`, not an overload — both take a bare
    /// trailing closure, which Swift can't disambiguate by inferred View
    /// content alone.
    ///
    /// Defaults `showBack` to false — a tile-grid screen carries its own
    /// HOME tile (see `V2Navigator`) instead of the chevron; every screen
    /// with a tile grid is expected to include one.
    func v2FloatingHeaderWithTiles<Tiles: View>(
        _ title: String,
        showBack: Bool = false,
        @ViewBuilder tiles: @escaping () -> Tiles
    ) -> some View {
        self
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top) {
                V2FloatingHeader(title: title, showBack: showBack, tiles: tiles)
            }
    }
}
