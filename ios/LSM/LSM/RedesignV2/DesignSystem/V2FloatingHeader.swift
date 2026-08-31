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
                            V2HeaderIconButton(systemImage: "chevron.left") { dismiss() }
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
            .padding(.bottom, 6)
        }
    }
}

/// The circular icon button seen throughout V2 floating headers — this
/// header's own back chevron, plus each game-detail screen's export/rename
/// pair, which had hand-rolled the same `.frame(width: 36, height: 36)
/// .background(V2Theme.cardBackground, in: Circle())` look three times over
/// (see V2 audit 3.6). For a `Menu`'s label, which supplies its own tap
/// target, use `V2HeaderIconLabel` instead — this wraps that same label in
/// a `Button`.
struct V2HeaderIconButton: View {
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            V2HeaderIconLabel(systemImage: systemImage)
        }
    }
}

/// Just the circular icon, no `Button` wrapper — for a `Menu`'s `label:`,
/// which already supplies its own tap target and can't nest another
/// `Button` inside it. Plain tappable icons should use `V2HeaderIconButton`
/// instead.
struct V2HeaderIconLabel: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.body.weight(.semibold))
            .foregroundStyle(V2Theme.textPrimary)
            .frame(width: 36, height: 36)
            .background(V2Theme.cardBackground, in: Circle())
    }
}

extension V2FloatingHeader where Trailing == EmptyView, Tiles == EmptyView {
    init(title: String, showBack: Bool = true) {
        self.title = title
        self.showBack = showBack
        // No tile grid to cover — the struct's 160/260 defaults are sized
        // for the tile-grid screens (Home/Games/Leagues/Players); a bare
        // title row only needs enough scrim to clear the status bar plus
        // its own content, or every pushed detail/form screen gets a
        // needless band of empty photo before its first card.
        self.scrimHeight = 60
        self.trailing = { EmptyView() }
        self.tiles = { EmptyView() }
    }
}

extension V2FloatingHeader where Tiles == EmptyView {
    init(title: String, showBack: Bool = true, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.showBack = showBack
        // See the no-trailing initializer above for why this is smaller
        // than the struct default.
        self.scrimHeight = 60
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
    /// row, both inside the same scrim — for every screen with a tile grid
    /// (Home, Games, Leagues, Players). Content scrolling underneath fades
    /// out over `headerHeight`/`V2FloatingHeaderFade.fadeRampHeight` rather
    /// than being hard-clipped by a plain `safeAreaInset` — this used to be
    /// Home's own hand-rolled `ZStack`+`.mask` (see `V2PreviewMenuView`'s
    /// git history), shared out here so every tile-grid screen fades the
    /// same way instead of Home fading and the rest cutting off flat.
    /// Distinct name from `v2FloatingHeader(_:trailing:)`, not an overload —
    /// both take a bare trailing closure, which Swift can't disambiguate by
    /// inferred View content alone.
    ///
    /// Defaults `showBack` to false — a tile-grid screen carries its own
    /// HOME tile (see `V2HomeTile`) instead of the chevron; every screen
    /// with a tile grid is expected to include one.
    ///
    /// Apply this *before* the screen's `.v2*Scene()` background modifier —
    /// the fade mask only ever covers `self` (the scrollable content); a
    /// scene applied after sits behind everything, un-masked, so the photo
    /// stays fully visible the whole way down while only the content in
    /// front of it fades.
    func v2FloatingHeaderWithTiles<Tiles: View>(
        _ title: String,
        showBack: Bool = false,
        headerHeight: CGFloat = V2FloatingHeaderFade.headerHeight,
        @ViewBuilder tiles: @escaping () -> Tiles
    ) -> some View {
        ZStack(alignment: .top) {
            self
                .safeAreaInset(edge: .top) {
                    Color.clear.frame(height: headerHeight + V2FloatingHeaderFade.fadeRampHeight)
                }
                .mask(alignment: .top) {
                    VStack(spacing: 0) {
                        Color.clear.frame(height: headerHeight)
                        LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                            .frame(height: V2FloatingHeaderFade.fadeRampHeight)
                        Color.black
                    }
                }
            V2FloatingHeader(title: title, showBack: showBack, scrimHeight: headerHeight, tiles: tiles)
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// Shared sizing for `.v2FloatingHeaderWithTiles`'s fade — one title row
/// plus `V2TileGrid`'s two tile rows measures ~170pt in practice; the
/// original Home-only constant was 220, then 185, both of which still left
/// a visibly dead band of scrim between where the real header content ended
/// and where scrolled content actually finished fading in (reported against
/// Home's "Favourites" section sitting noticeably below the HELP tile).
/// Fixed rather than measured (see `V2TileGrid`'s doc comment) — revisit if
/// Dynamic Type ever visibly misaligns it.
enum V2FloatingHeaderFade {
    static let headerHeight: CGFloat = 170
    static let fadeRampHeight: CGFloat = 14
}
