import SwiftUI

/// One shortcut tile — a stat (big number) or an action (icon), same visual
/// footprint either way, used in `V2TileGrid`. Shorter than the original
/// 3-tile row's padding (9pt vs 12pt vertical) now that there are two rows
/// of these instead of one.
struct V2Tile: View {
    var value: String?
    var icon: String?
    let label: String
    let color: Color
    /// True while this tile's own accordion panel is expanded (e.g. Home's
    /// LEAGUES/HELP tiles, which toggle an inline section instead of
    /// pushing a screen) — draws a colored ring so it reads as "open"
    /// rather than just a static shortcut.
    var isSelected: Bool = false

    var body: some View {
        VStack(spacing: 2) {
            if let value {
                Text(value)
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(color)
            } else if let icon {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(color)
            }
            MicroLabel(text: label)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .v2FloatingCard(cornerRadius: V2Theme.Radius.row)
        .overlay(
            RoundedRectangle(cornerRadius: V2Theme.Radius.row, style: .continuous)
                .stroke(isSelected ? color : .clear, lineWidth: 1.5)
        )
    }
}

/// An unfilled grid slot — occupies a tile's footprint (so the other five
/// keep their positions/sizing) without drawing a card, icon, or label. Used
/// where a screen doesn't yet have six real destinations rather than forcing
/// a sixth item that doesn't belong.
struct V2TileBlank: View {
    var body: some View {
        VStack(spacing: 2) {
            Text(" ").font(.system(.title3, design: .rounded).weight(.bold))
            MicroLabel(text: " ")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .opacity(0)
    }
}

/// Two rows of three `V2Tile`s — the persistent shortcut bar every V2 screen
/// with a floating header carries, its six tiles' destinations/actions
/// changing per screen (see `V2PreviewMenuView`/`GamesPortalViewV2`/
/// `PlayersViewV2`) but the visual system staying one thing.
struct V2TileGrid<Row1: View, Row2: View>: View {
    @ViewBuilder var row1: () -> Row1
    @ViewBuilder var row2: () -> Row2

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) { row1() }
            HStack(spacing: 8) { row2() }
        }
    }
}

/// The first tile of every pushed portal's grid (`GamesPortalViewV2`/
/// `LeaguesPortalViewV2`/`PlayersViewV2`) — dismisses back to Home. Factored
/// out after the same `Button { dismiss() } label: { V2Tile(icon:
/// "house.fill", …) }` had been hand-rolled three times over (see V2 audit
/// 3.5) — one more copy anywhere else should reach for this instead.
struct V2HomeTile: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button {
            dismiss()
        } label: {
            V2Tile(icon: "house.fill", label: "HOME", color: V2Theme.textSecondary)
        }
        .buttonStyle(.plain)
    }
}
