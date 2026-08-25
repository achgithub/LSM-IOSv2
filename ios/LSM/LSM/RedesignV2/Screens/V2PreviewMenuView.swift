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
/// normal section there, it's a shortcut, not a move), an "All games"
/// overview, then a menu of links to each restyled screen.
///
/// `.v2Header` is called with `showBack: false` — as the stack root there's
/// nothing to dismiss to, so the back chevron is omitted rather than shown
/// as a dead control.
struct V2PreviewMenuView: View {
    @Query(sort: \Game.createdAt, order: .reverse) private var games: [Game]
    @State private var wizardGame: Game?

    private var favouriteGames: [Game] { games.filter(\.isFavourite) }

    /// Approximate rendered height of `stickyHeader`, used to (a) push
    /// scrolled content down clear of it and (b) size the fade zone content
    /// scrolls through as it passes underneath. Fixed rather than measured
    /// (e.g. via a `GeometryReader` + `PreferenceKey`) — a reasonable
    /// tradeoff for now; revisit if Dynamic Type ever visibly misaligns it.
    private static let headerHeight: CGFloat = 220
    // The header has no background panel (free-floating title/bell/metrics,
    // see `stickyHeader`), so content scrolling underneath must already be
    // fully invisible for that entire span — not fading somewhere inside
    // it — or it shows through the gaps between the floating elements.
    // The actual fade ramp is a short zone just *below* that, so content
    // is already gone by the time it would reach the header at all, and
    // only reappears once genuinely clear of it.
    private static let fadeRampHeight: CGFloat = 40

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                VStack(spacing: 14) {
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
                // Clears the mask's fully-invisible zone *and* the fade
                // ramp below it — otherwise the first section starts
                // partway into the ramp and reads as already fading at
                // rest, before any scrolling has happened.
                .padding(.top, Self.headerHeight + Self.fadeRampHeight)
                .padding(.bottom, V2Theme.Spacing.section)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Fully hidden for the header's whole footprint, then ramps
            // back in just below it — see the constants' doc comments —
            // applied only to this ScrollView (not the background) so the
            // stadium image itself stays put.
            .mask(alignment: .top) {
                VStack(spacing: 0) {
                    Color.clear.frame(height: Self.headerHeight)
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                        .frame(height: Self.fadeRampHeight)
                    Color.black
                }
            }
            .v2StadiumScene()

            // Floating header, not scrolled content — sits above the masked
            // ScrollView in z-order, unaffected by its fade mask, and
            // (having no `.ignoresSafeArea()` of its own) sits below the
            // status bar automatically like any ordinary view.
            stickyHeader
        }
        // No `.v2Header`/system nav bar at all here, not even a transparent
        // one — a real `UINavigationController` nav bar still paints a
        // solid strip across the true top safe area regardless of
        // `.toolbarBackground(.hidden, ...)`, which cut the stadium image
        // off right under the status bar instead of letting it read as one
        // continuous scene. `stickyHeader` (a floating overlay, not a nav
        // bar) supplies the title/bell instead.
        .toolbar(.hidden, for: .navigationBar)
        // No .refreshable here — this is a static navigation menu, not a
        // live list. Games portal and the inbox itself both have their own
        // .refreshable/.task for the screens where it's actually live data.
        .fullScreenCover(item: $wizardGame) { game in GameWizardViewV2(game: game) }
    }

    /// Floating title/metrics header — fixed at the top of the screen
    /// (a `ZStack` sibling of the `ScrollView`, not part of its scrolled
    /// content), free over the stadium with no enclosing panel. The
    /// submission bell that used to sit here was dropped — Games' own
    /// SUBMISSIONS tile (see `GamesPortalViewV2`) already covers it, so this
    /// was a duplicate entry point.
    private var stickyHeader: some View {
        VStack(spacing: 14) {
            Text("Last Stand Manager")
                .font(V2Theme.Typography.pageTitle)
                .foregroundStyle(V2Theme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .center)
            if !games.isEmpty {
                GamesOverviewSummary(games: games)
            }
        }
        .padding(.horizontal, V2Theme.Spacing.horizontal)
        .padding(.top, 10)
        .padding(.bottom, 14)
        // No enclosing panel — title/bell/metrics float free over the
        // stadium the same way they did before this became a pinned
        // section header; only the metric tiles carry their own individual
        // card backing (see `GamesOverviewSummary`).
    }
}
