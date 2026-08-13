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
    @State private var wizardGame: Game?

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
                                    GameSummaryRow(game: game) { wizardGame = game }
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
                FootballDataCard()
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
        .fullScreenCover(item: $wizardGame) { game in GameWizardViewV2(game: game) }
    }
}

/// Expandable Home-screen card grouping "Leagues" and "Fixtures" under one
/// disclosure, plus an "Update football data" action refreshing both at
/// once — distinct from `SyncCoordinator`'s "Sync" (that pushes/pulls game
/// rounds and player submissions, not football provider data). See
/// `FootballDataStore` for the throttle/ad-gate rationale.
private struct FootballDataCard: View {
    @Environment(EnabledLeagues.self) private var enabled
    @State private var isExpanded = false
    @State private var store = FootballDataStore()

    private var updateLabel: String { store.isLoading ? "Updating…" : "Update football data" }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "sportscourt.fill")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(V2Theme.accent)
                            .frame(width: 22)
                        Text("Football Data")
                            .font(V2Theme.Typography.rowTitle)
                            .foregroundStyle(V2Theme.textPrimary)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(V2Theme.textSecondary)
                            .rotationEffect(.degrees(isExpanded ? 0 : -90))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if isExpanded {
                    VStack(spacing: 10) {
                        NavigationLink {
                            StandingsViewV2()
                        } label: {
                            MenuRow(systemImage: "list.number", title: "Leagues")
                        }
                        .buttonStyle(.plain)
                        NavigationLink {
                            MatchesViewV2()
                        } label: {
                            MenuRow(systemImage: "sportscourt", title: "Fixtures")
                        }
                        .buttonStyle(.plain)

                        Button {
                            store.refresh(leagues: enabled.leagues)
                        } label: {
                            HStack(spacing: 8) {
                                if store.isLoading {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                }
                                Text(updateLabel)
                                    .font(V2Theme.Typography.rowTitle.weight(.semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(V2Theme.pillBackground, in: RoundedRectangle(cornerRadius: V2Theme.Radius.row, style: .continuous))
                            .foregroundStyle(store.isThrottled ? V2Theme.textTertiary : V2Theme.textPrimary)
                        }
                        .buttonStyle(.plain)
                        .disabled(store.isLoading || store.isThrottled)

                        statusLine
                    }
                }
            }
        }
        .task(id: store.freshUntil) { await store.armClock() }
    }

    @ViewBuilder
    private var statusLine: some View {
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
    }
}
