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
    @Query(sort: \Game.createdAt, order: .reverse) private var games: [Game]
    @State private var showingNewGame = false
    @State private var showingGameLimit = false

    private var modesInPlay: [GameMode] {
        [.lms, .predictor, .killer].filter { mode in games.contains { $0.mode == mode } }
    }

    /// Mirrors `GamesListView.atGameLimit` — checked *before* presenting the
    /// create form, not just at Create-tap, so hitting the cap surfaces an
    /// explanatory alert instead of a silent no-op inside `NewGameViewV2`.
    private var atGameLimit: Bool {
        games.filter { $0.status != .complete }.count >= entitlements.maxActiveGames
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
                        ModeSectionCard(mode: mode, games: games.filter { $0.mode == mode })
                    }
                }
            }
            .padding(.horizontal, V2Theme.Spacing.horizontal)
            .padding(.vertical, V2Theme.Spacing.section)
        }
        .background(V2Theme.background.ignoresSafeArea())
        .v2Header("Games", trailingBadgeCount: badgeStore.pendingCount)
        .task { await badgeStore.refresh() }
        .refreshable { await badgeStore.refresh() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    if atGameLimit { showingGameLimit = true } else { showingNewGame = true }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(V2Theme.accent)
                }
                .accessibilityLabel("New Game")
            }
        }
        .sheet(isPresented: $showingNewGame) { NewGameViewV2() }
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

    private var title: String {
        switch mode {
        case .lms: return "Last Man Standing"
        case .predictor: return "Predictor"
        case .killer: return "Killer"
        }
    }

    private var icon: String {
        switch mode {
        case .lms: return "figure.walk"
        case .predictor: return "chart.bar.fill"
        case .killer: return "bolt.fill"
        }
    }

    private var modeColor: Color { V2Theme.Mode.color(for: mode) }
    @State private var isExpanded = true

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: icon)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(modeColor)
                        Text(title)
                            .font(.system(.title3, design: V2Theme.Mode.fontDesign(for: mode)).weight(.heavy))
                            .foregroundStyle(modeColor)
                        Spacer()
                        Text("\(games.count)")
                            .font(V2Theme.Typography.metadata)
                            .foregroundStyle(V2Theme.textTertiary)
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(V2Theme.textTertiary)
                            .rotationEffect(.degrees(isExpanded ? 0 : -90))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if isExpanded {
                    VStack(spacing: 10) {
                        ForEach(games) { game in
                            GameSummaryRow(game: game)
                        }
                    }
                }
            }
        }
    }
}

