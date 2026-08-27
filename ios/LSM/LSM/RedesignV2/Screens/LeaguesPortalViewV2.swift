import Combine
import SwiftUI

/// The Leagues portal — third of the app's four main screens (Home, Games,
/// Leagues, Players), reached by pushing from Home's LEAGUES tile like
/// GAMES/PLAYERS do. Its own tile grid (see `V2TileGrid`) doesn't push
/// further screens for Fixtures/Standings/Manage Leagues/Subscription —
/// tapping one expands that tile's content inline below, highlighted like a
/// selected tile, and collapses if tapped again. Same accordion mechanic
/// Home used to run LEAGUES/HELP through directly; now one level down, with
/// Fixtures/Standings/LeagueSettings/Subscription's own screen bodies
/// embedded as the panel content (their scene/header stripped — see each
/// file's doc comment — since this screen supplies both for all four).
struct LeaguesPortalViewV2: View {
    @Environment(EnabledLeagues.self) private var enabled
    @State private var store = FootballDataStore()
    @State private var expandedPanel: LeaguesPanelV2?

    private func toggle(_ panel: LeaguesPanelV2) {
        withAnimation(.easeInOut(duration: 0.2)) {
            expandedPanel = (expandedPanel == panel) ? nil : panel
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: V2Theme.Spacing.section) {
                statusCard
                panelContent
            }
            .padding(.horizontal, V2Theme.Spacing.horizontal)
            .padding(.top, V2Theme.Spacing.sceneTop)
            .padding(.bottom, V2Theme.Spacing.section)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .v2FloatingHeaderWithTiles("Leagues") {
            V2TileGrid {
                V2HomeTile()
                Button { toggle(.fixtures) } label: {
                    V2Tile(icon: "sportscourt", label: "FIXTURES", color: V2Theme.warning, isSelected: expandedPanel == .fixtures)
                }
                .buttonStyle(.plain)
                Button { toggle(.standings) } label: {
                    V2Tile(icon: "list.number", label: "STANDINGS", color: V2Theme.warning, isSelected: expandedPanel == .standings)
                }
                .buttonStyle(.plain)
            } row2: {
                Button { toggle(.manage) } label: {
                    V2Tile(icon: "slider.horizontal.3", label: "MANAGE", color: V2Theme.warning, isSelected: expandedPanel == .manage)
                }
                .buttonStyle(.plain)
                Button { toggle(.subscription) } label: {
                    V2Tile(icon: "star.fill", label: "SUBSCRIPTION", color: V2Theme.warning, isSelected: expandedPanel == .subscription)
                }
                .buttonStyle(.plain)
                V2TileBlank()
            }
        }
        // Applied after the header/fade modifier, not before — the fade
        // mask only ever covers the scrollable content, so the data room
        // photo behind it (this scene's `.background`) stays fully visible
        // the whole way down instead of fading out with it.
        .v2DataRoomScene()
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { tick in
            if store.isThrottled { store.now = tick }
        }
    }

    private var statusCard: some View {
        Card(floating: true) {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Football Data")
                statusLine
                ActionRow(
                    title: store.isLoading ? "Updating football data…" : "Update football data",
                    icon: "arrow.clockwise",
                    isEnabled: !store.isLoading && !store.isThrottled
                ) {
                    store.refresh(leagues: enabled.leagues)
                }
            }
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        VStack(alignment: .leading, spacing: 4) {
            if store.isThrottled, let freshUntil = store.freshUntil {
                let remaining = Duration.seconds(max(0, freshUntil.timeIntervalSince(store.now)))
                Text("Update available in \(remaining.formatted(.time(pattern: .minuteSecond)))")
                    .font(.caption2)
                    .foregroundStyle(V2Theme.textSecondary)
            } else if let lastRefreshed = store.lastRefreshed {
                Text("Updated \(lastRefreshed.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(V2Theme.textSecondary)
            } else if let errorMessage = store.errorMessage {
                Text(errorMessage)
                    .font(.caption2)
                    .foregroundStyle(V2Theme.danger)
            }
            Text(DataDisclaimer.text)
                .font(.caption2)
                .foregroundStyle(V2Theme.textTertiary)
        }
    }

    @ViewBuilder
    private var panelContent: some View {
        switch expandedPanel {
        case .fixtures:
            panel(title: "Fixtures") { MatchesViewV2() }
        case .standings:
            panel(title: "Standings") { StandingsViewV2() }
        case .manage:
            panel(title: "Manage Leagues") { LeagueSettingsViewV2() }
        case .subscription:
            panel(title: "Subscription") { SubscriptionSettingsViewV2() }
        case nil:
            EmptyView()
        }
    }

    private func panel<Content: View>(title: String, @ViewBuilder content: @escaping () -> Content) -> some View {
        Card(floating: true) {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: title)
                // Bounds the embedded screen's own `ScrollView` so a long
                // list (fixtures, standings) scrolls inside its panel
                // instead of trying to grow to fill the whole screen — see
                // the embedded screens' doc comments for why they still
                // carry `.frame(maxHeight: .infinity)` internally; this
                // caps what that resolves to here.
                content()
                    .frame(height: V2Theme.Spacing.inlinePanelHeight)
                    .clipShape(RoundedRectangle(cornerRadius: V2Theme.Radius.row, style: .continuous))
            }
        }
    }
}

/// Which of Leagues' four tiles (if any) is expanded inline below the tile
/// grid — at most one at a time (see `LeaguesPortalViewV2.toggle`).
enum LeaguesPanelV2 {
    case fixtures, standings, manage, subscription
}
