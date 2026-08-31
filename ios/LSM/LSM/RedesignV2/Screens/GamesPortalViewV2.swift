import SwiftUI
import SwiftData

/// The portal home: games grouped by mode (LMS / Predictor / Killer), each
/// mode as a capsule header (tap to collapse/expand) over its own games,
/// each game its own `GameSummaryRow`. Every number is computed from
/// existing shared logic (`PredictorStandings`, `KillerCardData`,
/// `Game.activePlayers`, the round's own `picks`/`predictions`/
/// `killerPredictions`) rather than re-derived here, so it can't drift from
/// the real share-card numbers.
///
/// Tapping the chevron pushes each mode's restyled detail view
/// (`GameDetailViewV2`/`PredictorGameDetailViewV2`/`KillerGameDetailViewV2`).
struct GamesPortalViewV2: View {
    /// Set when pushed from Home's Favourites card (see `FavouriteGameCard`)
    /// — Favourites is informational only and never jumps straight to game
    /// detail, so this is how it still gets you to the right place: land
    /// here, already scrolled to and briefly highlighting that one game's
    /// row, same list everything else uses.
    var focusGameID: UUID?
    @Environment(Entitlements.self) private var entitlements
    @Environment(SubmissionBadgeStore.self) private var badgeStore
    @Environment(PushCoordinator.self) private var pushCoordinator
    @Environment(\.modelContext) private var context
    @Query(sort: \Game.createdAt, order: .reverse) private var games: [Game]
    @State private var showingNewGame = false
    @State private var showingGameLimit = false
    @State private var showingPushPicker = false
    @State private var showingWizard = false
    @State private var highlightedGameID: UUID?

    private var modesInPlay: [GameMode] {
        [.lms, .predictor, .killer].filter { mode in games.contains { $0.mode == mode } }
    }

    /// Mirrors `GamesListView.atGameLimit` — checked *before* presenting the
    /// create form, not just at Create-tap, so hitting the cap surfaces an
    /// explanatory alert instead of a silent no-op inside `NewGameViewV2`.
    private var atGameLimit: Bool {
        games.filter { $0.status != .complete }.count >= entitlements.maxActiveGames
    }

    /// Same stat that used to live on Home's tile bar before Games got its
    /// own — reused here now that Games has tiles of its own to fill.
    private var activeCount: Int { games.filter { $0.status != .complete }.count }

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            LazyVStack(spacing: V2Theme.Spacing.section) {
                if games.isEmpty {
                    ContentUnavailableView {
                        Label("No games yet", systemImage: "trophy")
                    } description: {
                        Text("Tap + to create your first game.")
                    }
                    .padding(.top, 40)
                } else {
                    ForEach(modesInPlay, id: \.self) { mode in
                        ModeSectionCard(
                            mode: mode,
                            games: games.filter { $0.mode == mode },
                            highlightedGameID: highlightedGameID
                        )
                    }
                }
            }
            .padding(.horizontal, V2Theme.Spacing.horizontal)
            .padding(.top, V2Theme.Spacing.sceneTop)
            .padding(.bottom, V2Theme.Spacing.section)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Every action/stat this screen needs is one of the six tiles now
        // (Add/Push/Guided Setup/Submissions/Active/Submissions) — no
        // separate header icons, matching Home's tile grid instead of the
        // old four-icon toolbar.
        .v2FloatingHeaderWithTiles("Games") {
            V2TileGrid {
                V2HomeTile()
                Button {
                    showingPushPicker = true
                } label: {
                    V2Tile(
                        icon: "arrow.triangle.2.circlepath",
                        label: pushCoordinator.isPushing ? "PUSHING…" : "PUSH",
                        color: V2Theme.accent
                    )
                }
                .buttonStyle(.plain)
                .disabled(pushCoordinator.isPushing)
                Button {
                    if atGameLimit { showingGameLimit = true } else { showingNewGame = true }
                } label: {
                    V2Tile(icon: "plus", label: "ADD", color: V2Theme.accent)
                }
                .buttonStyle(.plain)
            } row2: {
                NavigationLink {
                    SubmissionInboxViewV2()
                } label: {
                    V2Tile(
                        value: badgeStore.pendingCount > 0 ? "\(badgeStore.pendingCount)" : nil,
                        icon: badgeStore.pendingCount > 0 ? nil : "bell",
                        label: "SUBMISSIONS",
                        color: badgeStore.pendingCount > 0 ? V2Theme.danger : V2Theme.textSecondary
                    )
                }
                .buttonStyle(.plain)
                V2Tile(value: "\(activeCount)", label: "ACTIVE", color: V2Theme.accent)
                Button {
                    showingWizard = true
                } label: {
                    V2Tile(icon: "wand.and.stars", label: "WIZARD", color: V2Theme.Mode.predictor)
                }
                .buttonStyle(.plain)
            }
        }
        // Applied after the header/fade modifier, not before — the fade
        // mask only ever covers the scrollable content, so the trophy room
        // photo behind it (this scene's `.background`) stays fully visible
        // the whole way down instead of fading out with it.
        .v2TrophyRoomScene()
        .task { await badgeStore.refresh() }
        // Only when pushed from Home's Favourites card — scroll to and
        // briefly ring the highlighted game's row, then clear it. Its own
        // `.task`, not chained after the badge refresh above: that's a
        // network call, and gating the scroll/highlight behind it meant a
        // slow or stalled fetch silently ate the whole effect — by the time
        // it resolved, the manager had already stopped looking. The sleep
        // before scrolling gives the just-pushed list a layout pass first;
        // without it `scrollTo` can fire before the row has a real position
        // to scroll to.
        .task {
            guard let focusGameID else { return }
            highlightedGameID = focusGameID
            try? await Task.sleep(nanoseconds: 300_000_000)
            withAnimation { proxy.scrollTo(focusGameID, anchor: .center) }
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            withAnimation { highlightedGameID = nil }
        }
        // Pull-to-refresh opens the same game picker as the PUSH tile —
        // both routes into Push go through an explicit per-game choice, so
        // pulling to refresh can't silently fan a push out across every
        // running game (each push is a billed Worker call).
        .refreshable { showingPushPicker = true }
        .v2PushSummary(pushCoordinator)
        .sheet(isPresented: $showingNewGame) { NewGameViewV2() }
        .sheet(isPresented: $showingPushPicker) {
            PushGamePickerViewV2(games: games) { gameIDs in
                Task { await pushCoordinator.push(context: context, gameIDs: gameIDs) }
            }
        }
        .fullScreenCover(isPresented: $showingWizard) { GameWizardViewV2() }
        .alert("Game limit reached", isPresented: $showingGameLimit) {
            Button("OK", role: .cancel) {}
        } message: {
            let limit = entitlements.maxActiveGames
            Text("Your \(entitlements.tier.label) plan includes \(limit) active games. Complete an existing game or upgrade to run more.")
        }
        }
    }
}

private struct ModeSectionCard: View {
    let mode: GameMode
    let games: [Game]
    var highlightedGameID: UUID?

    private var title: String { V2Theme.Mode.displayName(for: mode) }
    private var icon: String { V2Theme.Mode.icon(for: mode) }
    private var modeColor: Color { V2Theme.Mode.color(for: mode) }
    @State private var isExpanded = true

    var body: some View {
        // Each GameSummaryRow already carries its own floating card
        // background, so the section is its header (now its own compact
        // surface, not drawn straight over the photo — see the heading
        // critique this addressed) plus gapped rows over the stadium.
        VStack(alignment: .leading, spacing: 14) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(modeColor)
                    Text(title)
                        .font(.system(size: 23, design: V2Theme.Mode.fontDesign(for: mode)).weight(.bold))
                        .foregroundStyle(modeColor)
                    Spacer()
                    Text("\(games.count)")
                        .font(V2Theme.Typography.metadata)
                        .foregroundStyle(V2Theme.textSecondary)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(V2Theme.textSecondary)
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(V2Theme.cardBackground.opacity(0.9), in: Capsule())
                .overlay(Capsule().stroke(V2Theme.cardBorder.opacity(0.7)))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: 14) {
                    ForEach(games) { game in
                        GameSummaryRow(game: game)
                            .id(game.id)
                            .overlay(
                                RoundedRectangle(cornerRadius: V2Theme.Radius.card, style: .continuous)
                                    .stroke(highlightedGameID == game.id ? V2Theme.accent : .clear, lineWidth: 2)
                            )
                    }
                }
            }
        }
    }
}
