import SwiftUI
import SwiftData

/// The "Show Me" guided demo, presented as a full-screen **wizard** (mirroring
/// the real Guided Setup wizard's card style) rather than dropping the user into
/// the Games tab. Each step explains what's happening, shows a live preview of
/// the game as it's built, and surfaces a single, **highlighted** primary button
/// — the one thing to tap — to advance. Data is added progressively through
/// `DemoWalkthroughManager`/`DemoDataService` (the real services), two full
/// rounds, to a single winner.
struct DemoWizardView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var demo = DemoWalkthroughManager.shared
    /// Live demo game state — drives the preview as each step injects data.
    @Query(filter: #Predicate<Game> { $0.isDemoData }, sort: \Game.createdAt, order: .reverse)
    private var demoGames: [Game]

    private var game: Game? {
        if let id = demo.demoGameID { return demoGames.first { $0.id == id } }
        return demoGames.first
    }
    private var step: DemoStep { demo.currentStep }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                banner
                ScrollView {
                    VStack(spacing: 20) {
                        progress
                        stepCard
                        // The resume-tip step shows a swipe cue instead of the
                        // live roster — it's teaching navigation, not game state.
                        if step == .resumeTip {
                            SwipeToResumeCue()
                        } else if let game {
                            GameStatePreview(game: game)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 4)
                }
                Spacer(minLength: 0)
                controls
            }
            .appBackground()
            .navigationTitle("Guided Demo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Exit") { exit() }
                }
            }
            .onAppear {
                // Start (or restart) the demo when the wizard opens. Idempotent:
                // start() clears any prior demo data first.
                if !demo.isActive { demo.start(context: context) }
            }
        }
        .interactiveDismissDisabled()
    }

    // MARK: - Sections

    private var banner: some View {
        HStack(spacing: 8) {
            Image(systemName: "wand.and.rays")
            Text(step.bannerText)
                .font(.footnote.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(Color.accentColor)
    }

    private var progress: some View {
        VStack(spacing: 6) {
            Text("Step \(step.displayIndex) of \(DemoStep.count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ProgressView(value: Double(step.displayIndex), total: Double(DemoStep.count))
                .tint(.accentColor)
        }
    }

    private var stepCard: some View {
        VStack(spacing: 14) {
            Image(systemName: step.icon)
                .font(.system(size: 46))
                .foregroundStyle(.tint)
                .contentTransition(.symbolEffect(.replace))
            Text(step.title)
                .font(.title3.bold())
                .multilineTextAlignment(.center)
            Text(step.detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    /// The one thing to tap each step — visually highlighted so it's unmistakable,
    /// plus the management controls below it (kept clear of the primary action so
    /// nothing covers what's happening).
    private var controls: some View {
        VStack(spacing: 12) {
            Button {
                advance()
            } label: {
                HStack {
                    Text(step.primaryButtonTitle)
                    Image(systemName: step.isFinal ? "checkmark.circle.fill" : "arrow.right.circle.fill")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .demoHighlight()

            HStack(spacing: 12) {
                Button(role: .destructive) {
                    demo.clearAndRestart(context: context)
                } label: {
                    Label("Clear demo data", systemImage: "arrow.counterclockwise")
                        .font(.subheadline).frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button { exit() } label: {
                    Label("Exit demo", systemImage: "xmark")
                        .font(.subheadline).frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    // MARK: - Actions

    private func advance() {
        if step.isFinal {
            // Keep the finished demo game so the user can poke around it, then
            // close the wizard.
            demo.finish()
            dismiss()
        } else {
            withAnimation(.snappy) { demo.advance(context: context) }
        }
    }

    private func exit() {
        demo.exit(context: context)   // deletes all demo records
        dismiss()
    }
}

// MARK: - Live game-state preview

/// A compact, read-only mirror of the demo game so the user *watches it build*:
/// status + current round, and the roster with each player's live status badge.
private struct GameStatePreview: View {
    let game: Game

    private var sortedPlayers: [Player] {
        game.players.sorted { $0.entryNumber < $1.entryNumber }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(game.name, systemImage: "trophy")
                    .font(.subheadline.bold())
                Spacer()
                Text(game.status.label)
                    .font(.caption2.bold())
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(.tint.opacity(0.15), in: Capsule())
            }

            HStack(spacing: 16) {
                Label("Round \(game.currentRound?.roundNumber ?? 0)", systemImage: "calendar")
                Label("\(game.activePlayers.count) active", systemImage: "person.fill")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if sortedPlayers.isEmpty {
                Text("No players yet.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Divider()
                ForEach(sortedPlayers) { player in
                    HStack {
                        Text(player.name).font(.subheadline)
                        Spacer()
                        statusBadge(for: player)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .animation(.snappy, value: game.activePlayers.count)
        .animation(.snappy, value: game.players.count)
    }

    private func statusBadge(for player: Player) -> some View {
        let (text, color): (String, Color) = {
            switch player.status {
            case .active:     return (AppString("Active"), .green)
            case .eliminated: return (AppString("Out"), .red)
            case .winner:     return (AppString("Winner"), .yellow)
            }
        }()
        return Text(text)
            .font(.caption2.bold())
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }
}

// MARK: - Swipe-to-resume cue

/// A looping animation of the real gesture: a game row swiped to the right to
/// reveal the purple **Wizard** action (matching `GamesListView`'s leading swipe
/// action). Purely illustrative — it teaches how to resume a game later.
private struct SwipeToResumeCue: View {
    @State private var swiped = false
    /// How far the row slides to reveal the action beneath it.
    private let reveal: CGFloat = 96

    var body: some View {
        VStack(spacing: 10) {
            ZStack(alignment: .leading) {
                // The action revealed under the row on the leading edge.
                HStack {
                    VStack(spacing: 2) {
                        Image(systemName: "wand.and.stars")
                        Text("Wizard").font(.caption2.bold())
                    }
                    .foregroundStyle(.white)
                    .frame(width: reveal)
                    Spacer()
                }
                .background(Color.purple)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                // The game row that slides right to reveal it.
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Demo Game").font(.subheadline.bold())
                        Text("Round 1 · 3 active")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.background)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .offset(x: swiped ? reveal : 0)
                // A hand cue that travels with the swipe.
                .overlay(alignment: .leading) {
                    Image(systemName: "hand.point.up.left.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                        .offset(x: swiped ? reveal + 6 : 10, y: 14)
                }
            }
            .frame(height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            Text("Swipe right → tap Wizard to resume")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true).delay(0.3)) {
                swiped = true
            }
        }
    }
}

// MARK: - Highlight modifier

private struct DemoHighlight: ViewModifier {
    @State private var pulse = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(pulse ? 1.03 : 1.0)
            .shadow(color: Color.accentColor.opacity(pulse ? 0.55 : 0.2),
                    radius: pulse ? 14 : 6)
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
            .onAppear { pulse = true }
    }
}

private extension View {
    /// Draws steady attention to the single button the user should tap this step.
    func demoHighlight() -> some View { modifier(DemoHighlight()) }
}
