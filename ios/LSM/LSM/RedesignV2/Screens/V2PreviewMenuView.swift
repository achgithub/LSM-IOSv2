import SwiftUI
import SwiftData

/// Home — entry point into the V2 redesign. Reached via a row at the bottom
/// of Settings (see `SettingsView`), shown only when the user opts in via
/// `V2PreviewFlag` — off by default, works in every build, not `#if DEBUG`.
/// Leads with a Favourites shortcut (a game's star toggle lives on
/// `GameSummaryRow`, shared with the Games screen's per-mode sections —
/// favouriting here doesn't remove it from its normal section there, it's a
/// shortcut, not a move), then a menu of links to each restyled screen.
///
/// Pushed into Settings' own `NavigationStack` rather than owning one itself
/// — an embedded `NavigationStack` here, combined with `.v2Header`'s custom
/// back button, used to produce a stray extra back arrow (this view wrapped
/// its own root in `.v2Header`, which draws a back button even with nothing
/// to dismiss) on top of the real one Settings already provides.
struct V2PreviewMenuView: View {
    @Query(sort: \Game.createdAt, order: .reverse) private var games: [Game]
    @Environment(SubmissionBadgeStore.self) private var badgeStore

    private var favouriteGames: [Game] { games.filter(\.isFavourite) }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                if !favouriteGames.isEmpty {
                    Card {
                        VStack(alignment: .leading, spacing: 14) {
                            SectionHeader(title: "Favourites")
                            VStack(spacing: 10) {
                                ForEach(favouriteGames) { game in
                                    GameSummaryRow(game: game)
                                }
                            }
                        }
                    }
                }
                NavigationLink {
                    GamesPortalViewV2()
                } label: {
                    MenuRow(systemImage: "trophy", title: "Games")
                }
                .buttonStyle(.plain)
                NavigationLink {
                    PlayersViewV2()
                } label: {
                    MenuRow(systemImage: "person.2", title: "Players")
                }
                .buttonStyle(.plain)
                NavigationLink {
                    MatchesViewV2()
                } label: {
                    MenuRow(systemImage: "sportscourt", title: "Fixtures")
                }
                .buttonStyle(.plain)
                NavigationLink {
                    StandingsViewV2()
                } label: {
                    MenuRow(systemImage: "list.number", title: "Leagues")
                }
                .buttonStyle(.plain)
                NavigationLink {
                    SettingsViewV2()
                } label: {
                    MenuRow(systemImage: "gearshape", title: "Settings")
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, V2Theme.Spacing.horizontal)
            .padding(.vertical, V2Theme.Spacing.section)
        }
        .background(V2Theme.background.ignoresSafeArea())
        .v2Header("Home", trailingBadgeCount: badgeStore.pendingCount)
        // No .refreshable here — this is a static navigation menu, not a
        // live list, and the badge already refreshes on every appearance via
        // .task below. Pairing .refreshable with a .task that fires (and
        // finishes) on first appearance made the refresh control's reserved
        // space flash briefly at the top of the screen on load, not just on
        // an actual pull gesture. Games portal and the inbox itself both
        // already have their own .refreshable for the screens where it's
        // actually live data.
        .task { await badgeStore.refresh() }
    }
}
