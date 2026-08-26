import Combine
import SwiftUI
import SwiftData

/// Home — the root screen of the V2 experience, hosted inside its own
/// `NavigationStack` by `V2RootView` (see `AppRootView`, which picks V2RootView
/// vs. `RootTabView` per `V2PreviewFlag` — on by default, works in every
/// build, not `#if DEBUG`, since v1 needs to stay a real, live fallback).
/// Leads with the games overview summary, then a Favourites shortcut (a
/// game's star toggle lives on `GameSummaryRow`, shared with the Games
/// screen's per-mode sections — favouriting here doesn't remove it from its
/// normal section there, it's a shortcut, not a move), then an "All games"
/// overview. No menu list below that — every other destination is one of
/// the header's own tiles (see `GamesOverviewSummary`) or HELP's inline
/// panel (see `HomeHelpPanel` below).
///
/// Its floating header + fade is `.v2FloatingHeaderWithTiles`, the same
/// modifier every other tile-grid screen uses (Games/Leagues/Players) — this
/// was the pattern's original hand-rolled home (a `ZStack`+`.mask` composed
/// directly in this file) before it got shared out so the other three
/// screens faded content the same way instead of hard-clipping it. Called
/// with `showBack: false` — as the stack root there's nothing to dismiss to,
/// so the back chevron is omitted rather than shown as a dead control.
struct V2PreviewMenuView: View {
    @Query(sort: \Game.createdAt, order: .reverse) private var games: [Game]
    @State private var wizardGame: Game?
    /// Which of Home's inline accordion sections (if any) is expanded at the
    /// bottom of this screen — see `GamesOverviewSummary` (owns the HELP
    /// tile that toggles this) and `HomeHelpPanel` below (the content that
    /// renders when set).
    @State private var expandedPanel: HomePanel?

    private var favouriteGames: [Game] { games.filter(\.isFavourite) }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                // HELP doesn't push a screen — it expands inline right
                // here instead (see `HomePanel`), so it shows
                // immediately below the tiles rather than being scrolled
                // out of view under a long games list. LEAGUES pushes to
                // `LeaguesPortalViewV2` now, same as GAMES/PLAYERS.
                switch expandedPanel {
                case .help: HomeHelpPanel()
                case nil: EmptyView()
                }
                if !favouriteGames.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeader(title: "Favourites")
                        VStack(spacing: 14) {
                            ForEach(favouriteGames) { game in
                                GameSummaryRow(game: game) { wizardGame = game }
                            }
                        }
                    }
                }
                if !games.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeader(title: "All games", subtitle: "Drill into Games for the full per-mode view")
                        VStack(spacing: 14) {
                            ForEach(games) { game in
                                GameSummaryRow(game: game) { wizardGame = game }
                            }
                        }
                    }
                }
                // No menu list at all below the tiles anymore — all six
                // (Games/Leagues/Players/Sync/Help/Settings) are the
                // header's tile grid now (see `GamesOverviewSummary`).
            }
            .padding(.horizontal, V2Theme.Spacing.horizontal)
            .padding(.vertical, V2Theme.Spacing.section)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // The submission bell that used to sit in this header was dropped —
        // Games' own SUBMISSIONS tile (see `GamesPortalViewV2`) already
        // covers it, so this was a duplicate entry point.
        .v2FloatingHeaderWithTiles("Last Stand Manager") {
            if !games.isEmpty {
                GamesOverviewSummary(games: games, expandedPanel: $expandedPanel)
            }
        }
        // Applied after the header/fade modifier, not before — the fade
        // mask only ever covers the scrollable content, so the stadium
        // photo behind it (this scene's `.background`) stays fully visible
        // the whole way down instead of fading out with it.
        .v2StadiumScene()
        // No .refreshable here — this is a static navigation menu, not a
        // live list. Games portal and the inbox itself both have their own
        // .refreshable/.task for the screens where it's actually live data.
        .fullScreenCover(item: $wizardGame) { game in GameWizardViewV2(game: game) }
    }
}

/// HELP tile's inline content — replaces the old standalone `SettingsViewV2`
/// push destination (retired; nothing else pushed to it). The "New design"
/// v1 fallback toggle is the only thing unique to this screen; Profile/
/// Language/About/Report a Bug are still their own destinations, just
/// reached as ordinary rows here instead of a second tile grid inside a
/// second header.
private struct HomeHelpPanel: View {
    @AppStorage(V2PreviewFlag.key) private var v2Enabled = true

    var body: some View {
        Card(floating: true) {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "Help")
                VStack(alignment: .leading, spacing: 6) {
                    Toggle(isOn: $v2Enabled) {
                        MenuRow(systemImage: "sparkles", title: "New design", floating: true)
                    }
                    Text("Switch off to go back to the classic design.")
                        .font(V2Theme.Typography.metadata)
                        .foregroundStyle(V2Theme.textSecondary)
                }
                VStack(spacing: 8) {
                    NavigationLink {
                        ProfileSettingsViewV2()
                    } label: {
                        row("Profile", icon: "person.crop.circle.fill", tint: V2Theme.accent)
                    }
                    NavigationLink {
                        LanguageSettingsViewV2()
                    } label: {
                        row("Language", icon: "globe", tint: V2Theme.Mode.predictor)
                    }
                    NavigationLink {
                        AboutViewV2()
                    } label: {
                        row("About", icon: "info.circle.fill", tint: V2Theme.warning)
                    }
                    NavigationLink {
                        ReportBugViewV2()
                    } label: {
                        row("Report a Bug", icon: "ladybug.fill", tint: V2Theme.Mode.killer)
                    }
                }
            }
        }
    }

    private func row(_ title: String, icon: String, tint: Color) -> some View {
        HStack {
            Label(title, systemImage: icon)
            Spacer()
            Image(systemName: "chevron.right").font(.caption)
        }
        .foregroundStyle(tint)
    }
}
