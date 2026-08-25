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
