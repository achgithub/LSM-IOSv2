import Combine
import SwiftUI

/// The Leagues portal — third of the app's four main screens (Home, Games,
/// Leagues, Players), reached by pushing from Home's LEAGUES tile like
/// GAMES/PLAYERS do. Its own tile grid (see `V2TileGrid`) doesn't push
/// further screens for Fixtures/Standings/Subscription — tapping one expands
/// that tile's content inline below, highlighted like a selected tile, and
/// collapses if tapped again. Same accordion mechanic Home used to run
/// LEAGUES/HELP through directly; now one level down, with Fixtures/
/// Standings/Subscription's own screen bodies embedded as the panel content
/// (their scene/header stripped — see each file's doc comment — since this
/// screen supplies both for all three).
///
/// The fourth row-2 tile is SYNC, not a panel — the manual "Update football
/// data" action (its own 10-minute cooldown, `CacheTTL.updateFootballDataThrottle`),
/// firing directly on tap rather than expanding anything. It replaces the
/// old MANAGE tile, which pushed Manage Leagues inline here; that screen now
/// lives under Home's HELP panel instead (see `LeagueSettingsViewV2`) — this
/// slot went to the sync action so it wouldn't need its own card real estate
/// (see `FootballDataStore`).
struct LeaguesPortalViewV2: View {
    @Environment(EnabledLeagues.self) private var enabled
    @State private var store = FootballDataStore()
    @State private var expandedPanel: LeaguesPanelV2?
    /// Fixtures' filter card (league/team/home-away/matchday/date pills)
    /// starts hidden so opening Fixtures shows the match list immediately,
    /// no scrolling past a filter card first. SEARCH reveals it; filters
    /// stay applied to the list even after it's hidden again — only the
    /// controls disappear, not the filtering. Meaningless outside Fixtures,
    /// so SEARCH is disabled unless that's the open panel (see body).
    @State private var showFixturesFilter = false

    private func toggle(_ panel: LeaguesPanelV2) {
        withAnimation(.easeInOut(duration: 0.2)) {
            expandedPanel = (expandedPanel == panel) ? nil : panel
            if expandedPanel != .fixtures { showFixturesFilter = false }
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: V2Theme.Spacing.section) {
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
                Button {
                    store.refresh(leagues: enabled.leagues)
                } label: {
                    V2Tile(icon: "arrow.clockwise", label: store.isLoading ? "SYNCING…" : "SYNC", color: V2Theme.warning)
                }
                .buttonStyle(.plain)
                .disabled(store.isLoading || store.isThrottled)
                .opacity(store.isLoading || store.isThrottled ? 0.4 : 1)
                Button { toggle(.subscription) } label: {
                    V2Tile(icon: "star.fill", label: "SUBSCRIPTION", color: V2Theme.warning, isSelected: expandedPanel == .subscription)
                }
                .buttonStyle(.plain)
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showFixturesFilter.toggle() }
                } label: {
                    V2Tile(icon: "magnifyingglass", label: "SEARCH", color: V2Theme.warning, isSelected: showFixturesFilter)
                }
                .buttonStyle(.plain)
                .disabled(expandedPanel != .fixtures)
            }
        }
        // Applied after the header/fade modifier, not before — the fade
        // mask only ever covers the scrollable content, so the data room
        // photo behind it (this scene's `.background`) stays fully visible
        // the whole way down instead of fading out with it.
        .v2DataRoomScene()
        // Ticks `store.now` so SYNC's `isThrottled` (and therefore its
        // disabled/dimmed state) flips back off once the 10-minute cooldown
        // lapses, without needing this screen to be re-tapped.
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { tick in
            if store.isThrottled { store.now = tick }
        }
    }

    @ViewBuilder
    private var panelContent: some View {
        switch expandedPanel {
        case .fixtures:
            panel(title: "Fixtures") { MatchesViewV2(showFilter: $showFixturesFilter) }
        case .standings:
            panel(title: "Standings") { StandingsViewV2() }
        case .subscription:
            panel(title: "Subscription") { SubscriptionSettingsViewV2() }
        case nil:
            EmptyView()
        }
    }

    private func panel<Content: View>(title: LocalizedStringKey, @ViewBuilder content: @escaping () -> Content) -> some View {
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

/// Which of Leagues' panel-backed tiles (if any) is expanded inline below
/// the tile grid — at most one at a time (see `LeaguesPortalViewV2.toggle`).
/// SYNC isn't here — it fires directly on tap, no panel to expand.
enum LeaguesPanelV2 {
    case fixtures, standings, subscription
}
