import SwiftUI
import SwiftData

/// Home's six shortcut tiles (see `V2PreviewMenuView`) — replaces the old
/// three-tile row plus the menu list's separate Games/Players/Settings rows
/// and the header's standalone Sync button; this is now the only way in for
/// all of it. Cheap by construction: `activeCount` is a simple filter over
/// `games` (bounded by `Entitlements.maxActiveGames`, not per-fixture data),
/// `members.count`/`enabled.ids.count` are each their own `@Query`/
/// environment count — none of this adds new O(players) work beyond what's
/// already paid elsewhere.
struct GamesOverviewSummary: View {
    let games: [Game]
    /// The real roster count — not a sum of each game's player list (a
    /// player in three games would triple-count that way), the actual
    /// number of distinct `RosterMember`s, same source `PlayersViewV2` uses.
    @Query private var members: [RosterMember]
    @Environment(EnabledLeagues.self) private var enabled
    @Environment(SyncCoordinator.self) private var syncCoordinator
    @Environment(\.modelContext) private var context
    @State private var showingSyncPicker = false

    private var activeCount: Int { games.filter { $0.status != .complete }.count }

    var body: some View {
        V2TileGrid {
            NavigationLink {
                GamesPortalViewV2()
            } label: {
                V2Tile(value: "\(activeCount)", label: "GAMES", color: V2Theme.accent)
            }
            .buttonStyle(.plain)
            NavigationLink {
                FootballDataViewV2()
            } label: {
                V2Tile(value: "\(enabled.ids.count)", label: "LEAGUES", color: V2Theme.warning)
            }
            .buttonStyle(.plain)
            NavigationLink {
                PlayersViewV2()
            } label: {
                V2Tile(value: "\(members.count)", label: "PLAYERS", color: V2Theme.Mode.predictor)
            }
            .buttonStyle(.plain)
        } row2: {
            Button {
                showingSyncPicker = true
            } label: {
                V2Tile(
                    icon: "arrow.triangle.2.circlepath",
                    label: syncCoordinator.isSyncing ? "SYNCING…" : "SYNC",
                    color: V2Theme.accent
                )
            }
            .buttonStyle(.plain)
            .disabled(syncCoordinator.isSyncing)
            // SettingsViewV2 is now the Help hub (Profile/Language/About/
            // Report a Bug) — dedicated Settings tile is gone, its other
            // former contents moved to Football Data (Subscription/Leagues)
            // and Players (Roster) — see 2026-08-25 restructure.
            NavigationLink {
                SettingsViewV2()
            } label: {
                V2Tile(icon: "questionmark.circle", label: "HELP", color: V2Theme.warning)
            }
            .buttonStyle(.plain)
            V2TileBlank()
        }
        .sheet(isPresented: $showingSyncPicker) {
            SyncGamePickerViewV2(games: games) { gameIDs in
                Task { await syncCoordinator.sync(context: context, gameIDs: gameIDs) }
            }
        }
    }
}
