import Combine
import SwiftUI
import SwiftData

/// Home — the root screen of the V2 experience, hosted inside its own
/// `NavigationStack` by `V2RootView` (see `AppRootView`, which picks V2RootView
/// vs. `RootTabView` per `V2PreviewFlag` — on by default, works in every
/// build, not `#if DEBUG`, since v1 needs to stay a real, live fallback).
/// Leads with the games overview summary, then a Favourites shortcut — a
/// game's star toggle lives on `GameSummaryRow` in the Games portal, not
/// here (see `FavouriteGameCard`, an informational-only card; tapping it
/// jumps to that game's row in the Games portal, not straight to game
/// detail). No full games list here — that's the Games portal's job (its
/// own GAMES tile above), so Home doesn't repeat it. No menu list either —
/// every other destination is one of the header's own tiles (see
/// `GamesOverviewSummary`) or HELP's inline panel (see `HomeHelpPanel`
/// below).
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
    /// Which of Home's inline accordion sections (if any) is expanded at the
    /// bottom of this screen — see `GamesOverviewSummary` (owns the HELP
    /// tile that toggles this) and `HomeHelpPanel` below (the content that
    /// renders when set).
    @State private var expandedPanel: HomePanel?
    @Environment(EnabledLeagues.self) private var enabledLeagues
    @Environment(Entitlements.self) private var entitlements
    @Environment(\.scenePhase) private var scenePhase

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
                                FavouriteGameCard(game: game)
                            }
                        }
                    }
                }
                // No "All games" list here — that's what the Games portal
                // itself is for (its own GAMES tile above); duplicating the
                // full list on Home just repeated it a scroll away.
                //
                // No menu list at all below the tiles anymore — all six
                // (Games/Leagues/Players/Sync/Help/Settings) are the
                // header's tile grid now (see `GamesOverviewSummary`).
            }
            .padding(.horizontal, V2Theme.Spacing.horizontal)
            .padding(.top, V2Theme.Spacing.sceneTop)
            .padding(.bottom, V2Theme.Spacing.section)
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
        //
        // Auto-refresh — see docs/sync-refresh-policy.md. One-shot on
        // appear (relaxed ladder — no-ops for Free via `refreshIfDue`'s own
        // `removesAds` guard), plus the live-match loop below.
        .onAppear {
            Task { await SyncScheduler.shared.refreshIfDue(games: games, leagues: enabledLeagues.leagues, entitlements: entitlements) }
        }
        // Live-match tight loop — `leagues3/5/7` only (`canUseCloud`, same
        // boundary as PWA access; `noAds` gets the relaxed ladder above but
        // not this). Cheap 60s local-only check (`isAnyFixtureActive` never
        // hits the network) so it can run continuously while Home is
        // visible; an actual network refresh only happens at most every 10
        // min, and only while a fixture is genuinely in its active window —
        // see `CacheTTL.liveWindowLead`/`standingsLiveWindow`. `.task`
        // (not a bare `Task` in `.onAppear`) cancels automatically when
        // this view disappears; the `scenePhase` guard additionally stops
        // it firing while merely backgrounded, since disappearing and
        // backgrounding aren't the same event.
        .task {
            guard entitlements.canUseCloud else { return }
            var lastPoll = Date.distantPast
            while !Task.isCancelled {
                if scenePhase == .active,
                   SyncScheduler.isAnyFixtureActive(games: games),
                   Date().timeIntervalSince(lastPoll) >= 600 {
                    await SyncScheduler.shared.refreshIfDue(games: games, leagues: enabledLeagues.leagues, entitlements: entitlements)
                    lastPoll = Date()
                }
                try? await Task.sleep(for: .seconds(60))
            }
        }
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
                        LeagueSettingsViewV2()
                    } label: {
                        row("Manage Leagues", icon: "slider.horizontal.3", tint: V2Theme.warning)
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
                    // POC only — see docs/keepy-uppy-poc-scope.md. Not a
                    // shipping mode, deliberately kept out of the Games
                    // picker. Needs to build in Release (not just DEBUG)
                    // since motion feel can only be validated via TestFlight
                    // on a physical device, not the Simulator.
                    NavigationLink {
                        KeepyUppyViewV2()
                    } label: {
                        row("Keepy-Uppy (POC)", icon: "figure.soccer", tint: V2Theme.Mode.predictor)
                    }
                }
                Text(DataDisclaimer.text)
                    .font(.caption2)
                    .foregroundStyle(V2Theme.textTertiary)
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
