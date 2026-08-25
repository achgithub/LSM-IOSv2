import SwiftUI
import SwiftData

/// The portal home: games grouped by mode (LMS / Predictor / Killer), each
/// mode as one main card containing its games nested inside. Each game row
/// leads with manager-relevant status — submissions in vs. due date — then a
/// mode-appropriate standing (LMS: who's still in; Killer: lives; Predictor:
/// points table), collapsed to a couple of entries with a "+more" toggle that
/// expands the card in place. Every number is computed from existing shared
/// logic (`PredictorStandings`, `KillerCardData`, `Game.activePlayers`, the
/// round's own `picks`/`predictions`/`killerPredictions`) rather than
/// re-derived here, so it can't drift from the real share-card numbers.
///
/// Tapping the chevron pushes the *existing* per-mode detail view — those
/// haven't been restyled yet; that's the next phase of the V2 build.
struct GamesPortalViewV2: View {
    @Environment(Entitlements.self) private var entitlements
    @Environment(SubmissionBadgeStore.self) private var badgeStore
    @Environment(SyncCoordinator.self) private var syncCoordinator
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Game.createdAt, order: .reverse) private var games: [Game]
    @State private var showingNewGame = false
    @State private var showingGameLimit = false
    @State private var showingSyncSummary = false
    @State private var showingSyncPicker = false
    @State private var showingWizard = false
    @State private var wizardGame: Game?

    private var modesInPlay: [GameMode] {
        [.lms, .predictor, .killer].filter { mode in games.contains { $0.mode == mode } }
    }

    /// Mirrors `GamesListView.atGameLimit` — checked *before* presenting the
    /// create form, not just at Create-tap, so hitting the cap surfaces an
    /// explanatory alert instead of a silent no-op inside `NewGameViewV2`.
    private var atGameLimit: Bool {
        games.filter { $0.status != .complete }.count >= entitlements.maxActiveGames
    }

    /// Same two stats that used to live on Home's tile bar before Games got
    /// its own — reused here now that Games has tiles of its own to fill.
    private var activeCount: Int { games.filter { $0.status != .complete }.count }
    private var dueCount: Int {
        games.filter { ManagerRoundStatus.make(for: $0)?.tint == V2Theme.warning }.count
    }

    /// Brief post-sync summary ("3 games synced, 2 pending submissions"),
    /// surfacing errors instead of the pending count when any game failed to
    /// push. Reads `syncCoordinator.lastSyncResult`, set once `sync()`
    /// finishes — see `SyncCoordinator`.
    private var syncSummaryText: String {
        guard let result = syncCoordinator.lastSyncResult else { return "" }
        let gamesPart = result.gamesPushed == 1 ? "1 game synced" : "\(result.gamesPushed) games synced"
        let skippedPart: String = {
            guard !result.skippedNoOpenRound.isEmpty else { return "" }
            let count = result.skippedNoOpenRound.count
            return count == 1 ? ", 1 waiting for a round" : ", \(count) waiting for a round"
        }()
        // A retry-driven push to a game the manager didn't select this time
        // (the outbox catching up on a previously dropped write) — surfaced
        // so it's visible, not silent.
        let retriedPart: String = {
            guard result.retriedOutstanding > 0 else { return "" }
            return result.retriedOutstanding == 1 ? ", 1 retried" : ", \(result.retriedOutstanding) retried"
        }()
        if result.errors.isEmpty {
            let pendingPart = result.pendingCount == 1 ? "1 pending submission" : "\(result.pendingCount) pending submissions"
            return "\(gamesPart), \(pendingPart)\(skippedPart)\(retriedPart)"
        } else {
            let errorPart = result.errors.count == 1 ? "1 game failed" : "\(result.errors.count) games failed"
            return "\(gamesPart) — \(errorPart)\(skippedPart)\(retriedPart)"
        }
    }

    private func performSync(gameIDs: Set<UUID>) async {
        await syncCoordinator.sync(context: context, gameIDs: gameIDs)
        withAnimation { showingSyncSummary = true }
        try? await Task.sleep(nanoseconds: 3_500_000_000)
        withAnimation { showingSyncSummary = false }
    }

    var body: some View {
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
                        ModeSectionCard(mode: mode, games: games.filter { $0.mode == mode }) { game in
                            wizardGame = game
                        }
                    }
                }
            }
            .padding(.horizontal, V2Theme.Spacing.horizontal)
            .padding(.vertical, V2Theme.Spacing.section)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .v2TrophyRoomScene()
        // Every action/stat this screen needs is one of the six tiles now
        // (Add/Sync/Guided Setup/Submissions/Active/Due) — no separate
        // header icons, matching Home's tile grid instead of the old
        // four-icon toolbar.
        .v2FloatingHeaderWithTiles("Games") {
            V2TileGrid {
                Button {
                    dismiss()
                } label: {
                    V2Tile(icon: "house.fill", label: "HOME", color: V2Theme.textSecondary)
                }
                .buttonStyle(.plain)
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
                    V2Tile(icon: "wand.and.stars", label: "SETUP", color: V2Theme.Mode.predictor)
                }
                .buttonStyle(.plain)
            }
        }
        .task { await badgeStore.refresh() }
        // Pull-to-refresh opens the same game picker as the toolbar button —
        // both routes into Sync go through an explicit per-game choice, so
        // pulling to refresh can't silently fan a push out across every
        // running game (each push is a billed Worker call).
        .refreshable { showingSyncPicker = true }
        .overlay(alignment: .top) {
            if showingSyncSummary, let result = syncCoordinator.lastSyncResult {
                Card {
                    HStack(spacing: 10) {
                        Image(systemName: result.errors.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(result.errors.isEmpty ? V2Theme.accent : V2Theme.warning)
                        Text(syncSummaryText)
                            .font(V2Theme.Typography.metadata)
                            .foregroundStyle(V2Theme.textPrimary)
                    }
                }
                .padding(.horizontal, V2Theme.Spacing.horizontal)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .sheet(isPresented: $showingNewGame) { NewGameViewV2() }
        .sheet(isPresented: $showingSyncPicker) {
            SyncGamePickerViewV2(games: games) { gameIDs in
                Task { await performSync(gameIDs: gameIDs) }
            }
        }
        .fullScreenCover(isPresented: $showingWizard) { GameWizardViewV2() }
        .fullScreenCover(item: $wizardGame) { game in GameWizardViewV2(game: game) }
        .alert("Game limit reached", isPresented: $showingGameLimit) {
            Button("OK", role: .cancel) {}
        } message: {
            let limit = entitlements.maxActiveGames
            Text("Your \(entitlements.tier.label) plan includes \(limit) active games. Complete an existing game or upgrade to run more.")
        }
    }
}

private struct ModeSectionCard: View {
    let mode: GameMode
    let games: [Game]
    var onResume: (Game) -> Void = { _ in }

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
                        GameSummaryRow(game: game) { onResume(game) }
                    }
                }
            }
        }
    }
}
