import SwiftUI
import UIKit

/// Standalone POC screen for the keepy-uppy game (docs/keepy-uppy-poc-scope.md).
/// Reached only from a row in Settings' Help panel (see
/// `V2PreviewMenuView`'s `HomeHelpPanel`). Deliberately outside the
/// Games/LMS/Predictor/Killer mode infrastructure, since this doesn't
/// create a `Game` and isn't a shipping mode.
///
/// Originally a Core Motion (phone-tilt/flick) control experiment — dropped
/// entirely after on-device testing across several rounds found detection
/// unreliable, tilt-based aiming imprecise, and the whole flick-to-kick
/// metaphor not a good fit regardless of tuning. Touch (drag to position
/// the boot, swipe up to kick) replaced it as the sole control scheme; see
/// git history on this file for the motion-based attempt if it's ever
/// worth revisiting with a different sensor approach.
struct KeepyUppyViewV2: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var game = KeepyUppyGame()
    @State private var hapticsEnabled = true

    @State private var lastTickDate: Date?
    @State private var flashFeedback: KickFeedback?
    @State private var tierBannerText: String?
    @State private var obstacleFlashActive = false

    // Tracks the drag to detect an upward flick as a kick attempt — see
    // the drag gesture below. Reset whenever the finger lifts.
    @State private var lastDragLocation: CGPoint?
    @State private var lastDragTime: Date?
    @State private var swipeArmed = true

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // One continuous gesture does both jobs: the boot follows
                // your thumb (positioning), and a fast upward flick within
                // that same drag is a kick attempt, with power scaled by
                // how fast the flick was. Positioning alone (a slow drag)
                // never scores — only an actual flick arms `requestKick`,
                // same as Tap Kick would. Attached
                // to this background layer, not the whole ZStack, so a
                // touch that starts on an actual button is claimed by that
                // button first; only touches on open field space drive this.
                Color(.systemBackground)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in handleDragChanged(value, fieldSize: geo.size) }
                            .onEnded { _ in
                                lastDragLocation = nil
                                lastDragTime = nil
                                swipeArmed = true
                            }
                    )
                tickDriver
                windsock(in: geo.size)
                obstaclesView(in: geo.size)
                foot(in: geo.size)
                ball(in: geo.size)
                feedbackFlash
                obstacleFlash
                VStack(spacing: 16) {
                    hud
                    if let tierBannerText {
                        tierBanner(tierBannerText)
                    }
                    Spacer()
                    if game.isGameOver {
                        gameOverPanel
                    }
                    controls
                }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: tierBannerText)
                .padding()
            }
        }
        .navigationTitle("Keepy-Uppy (POC)")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { game.pause() }
        }
        .onChange(of: game.lastFeedback) { _, feedback in
            guard let feedback else { return }
            fireHaptic(for: feedback)
            flashFeedback = feedback
            game.lastFeedback = nil
            Task {
                try? await Task.sleep(nanoseconds: 400_000_000)
                if flashFeedback == feedback { flashFeedback = nil }
            }
        }
        .onChange(of: game.tierAnnouncement) { _, message in
            guard let message else { return }
            tierBannerText = message
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            game.tierAnnouncement = nil
            Task {
                try? await Task.sleep(nanoseconds: 1_600_000_000)
                if tierBannerText == message { tierBannerText = nil }
            }
        }
        .onChange(of: game.obstacleHitEvent) { _, event in
            guard let event else { return }
            fireObstacleHaptic(for: event.kind)
            obstacleFlashActive = true
            game.obstacleHitEvent = nil
            Task {
                try? await Task.sleep(nanoseconds: 300_000_000)
                obstacleFlashActive = false
            }
        }
    }

    // MARK: - Touch control

    /// Points/sec of upward finger speed needed to count as a kick flick,
    /// vs. just repositioning the boot.
    private let swipeTriggerSpeed: CGFloat = 500
    /// Upward speed at which a swipe is treated as full (1.0) power —
    /// scaled linearly below that.
    private let swipeMaxPowerSpeed: CGFloat = 1800
    /// Speed the finger has to drop back below before another flick can
    /// arm, so one continuous fast motion can't fire more than one kick.
    private let swipeResetSpeed: CGFloat = 150

    private func handleDragChanged(_ value: DragGesture.Value, fieldSize: CGSize) {
        let clampedX = min(max(value.location.x, 0), fieldSize.width)
        game.footX = clampedX / fieldSize.width

        defer {
            lastDragLocation = value.location
            lastDragTime = Date()
        }

        guard let lastLocation = lastDragLocation, let lastTime = lastDragTime else { return }
        let dt = Date().timeIntervalSince(lastTime)
        guard dt > 0 else { return }

        // Screen y grows downward, so a finger moving up is a *decrease*
        // in y — this is positive exactly when the finger is moving up.
        let upwardSpeed = (lastLocation.y - value.location.y) / CGFloat(dt)

        if upwardSpeed > swipeTriggerSpeed, swipeArmed {
            swipeArmed = false
            let power = min(max((upwardSpeed - swipeTriggerSpeed) / (swipeMaxPowerSpeed - swipeTriggerSpeed), 0), 1)
            game.requestKick(power: Double(power))
        }
        if upwardSpeed < swipeResetSpeed {
            swipeArmed = true
        }
    }

    // MARK: - Physics tick

    /// Invisible layer whose only job is advancing `game`'s physics once
    /// per frame. A `TimelineView` drives it rather than a manual `Timer`;
    /// mutating state directly in the timeline closure (rather than in
    /// `.onChange`) would trigger "modifying state during view update", so
    /// the actual `tick` call happens on the date change instead.
    private var tickDriver: some View {
        TimelineView(.animation) { timeline in
            Color.clear
                .onChange(of: timeline.date) { _, newDate in
                    let delta = lastTickDate.map { newDate.timeIntervalSince($0) } ?? 0
                    lastTickDate = newDate
                    game.tick(deltaTime: CGFloat(delta))
                }
        }
    }

    // MARK: - Field

    /// Corner-flag-style windsock — a football-native stand-in for an
    /// abstract compass, since a real corner flag already tells players
    /// wind direction. Only appears once score crosses into a wind tier
    /// (docs: "starts easy, no wind"); rotation/flutter speed reflect
    /// `windSpeed`, giving the same dev-aid-turned-player-feedback role as
    /// the power meter.
    @ViewBuilder
    private func windsock(in size: CGSize) -> some View {
        if game.isWindActive {
            VStack(spacing: 2) {
                Text("🚩")
                    .font(.system(size: 30))
                    .rotationEffect(.degrees(Double(game.windSpeed) * 50))
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.5), value: game.windSpeed)
                Text(windSpeedLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .position(x: size.width - 40, y: 70)
        }
    }

    private var windSpeedLabel: String {
        let mph = Int(abs(game.windSpeed) * 40)
        guard mph > 0 else { return "Calm" }
        return "\(mph) mph \(game.windSpeed >= 0 ? "→" : "←")"
    }

    /// Seagulls (🐦, straight line) and drones (🚁, zig-zag —
    /// `KeepyUppyGame.obstacleY` rides a sine wave on top of the straight
    /// travel) — both fly in from off-screen and knock the ball on contact.
    private func obstaclesView(in size: CGSize) -> some View {
        ForEach(game.obstacles) { obstacle in
            Text(obstacle.kind == .seagull ? "🐦" : "🚁")
                .font(.system(size: 30))
                .scaleEffect(x: obstacle.velocityX >= 0 ? 1 : -1, y: 1)
                .position(x: obstacle.x * size.width, y: game.obstacleY(obstacle) * size.height)
        }
    }

    /// Brief tint on any obstacle collision — distinct from `feedbackFlash`
    /// (which is about kick *timing*, not an environmental hazard) so a hit
    /// reads as "something external happened," not a missed touch.
    @ViewBuilder
    private var obstacleFlash: some View {
        if obstacleFlashActive {
            Color.purple.opacity(reduceMotion ? 0.15 : 0.25)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }

    private func tierBanner(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.subheadline.bold())
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .frame(maxWidth: .infinity)
            .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
    }

    /// Always rendered — the boot is now the primary control (drag to
    /// position it) regardless of whether motion controls are on, not
    /// something that only exists when motion is active.
    private func foot(in size: CGSize) -> some View {
        let x = game.footX * size.width
        let y = game.footY * size.height
        let reachRadius = game.footReach * size.width
        return ZStack {
            // Reach ring — a tuning/feedback aid showing how close the
            // ball needs to be, same spirit as the power meter
            // (docs/keepy-uppy-poc-scope.md "development aids").
            Circle()
                .stroke(V2Theme.accent.opacity(0.35), lineWidth: 1.5)
                .frame(width: reachRadius * 2, height: reachRadius * 2)
                .position(x: x, y: y)
            Text("🥾")
                .font(.system(size: 40))
                .position(x: x, y: y)
        }
    }

    private func ball(in size: CGSize) -> some View {
        Text("⚽️")
            .font(.system(size: 44))
            .position(x: game.ball.x * size.width, y: game.ball.y * size.height)
    }

    @ViewBuilder
    private var feedbackFlash: some View {
        if let flashFeedback {
            RoundedRectangle(cornerRadius: 0)
                .fill(flashColor(flashFeedback).opacity(reduceMotion ? 0.18 : 0.28))
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: flashFeedback)
        }
    }

    private func flashColor(_ feedback: KickFeedback) -> Color {
        switch feedback {
        case .perfect, .good: return .green
        case .earlyOrLate: return .orange
        case .miss: return .red
        }
    }

    // MARK: - HUD

    private var hud: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("Score").font(.caption).foregroundStyle(.secondary)
                Text("\(game.score)").font(.title2.bold())
            }
            Spacer()
            VStack(alignment: .trailing) {
                Text("Best").font(.caption).foregroundStyle(.secondary)
                Text("\(game.bestScore)").font(.title2.bold())
            }
        }
    }

    // MARK: - Game over

    private var gameOverPanel: some View {
        VStack(spacing: 4) {
            Text("Game Over").font(.headline)
            Text("Score: \(game.score) · Best: \(game.bestScore)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                startRestartButton
                if game.isRunning {
                    Button(game.isPaused ? "Resume" : "Pause") {
                        game.isPaused ? game.resume() : game.pause()
                    }
                    .buttonStyle(.bordered)
                }
            }

            if game.isRunning, !game.isPaused {
                Button {
                    game.performTapKick()
                } label: {
                    Text("TAP KICK").font(.headline).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            Toggle("Haptics", isOn: $hapticsEnabled)
        }
    }

    private var startRestartButton: some View {
        Button(game.isGameOver ? "Restart" : "Start") {
            game.start()
        }
        .buttonStyle(.borderedProminent)
        .disabled(game.isRunning && !game.isGameOver)
    }

    // MARK: - Haptics

    private func fireHaptic(for feedback: KickFeedback) {
        guard hapticsEnabled else { return }
        switch feedback {
        case .perfect:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .good:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .earlyOrLate:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .miss:
            // Deliberately subtle — a miss shouldn't feel like a strong
            // vibration/error buzz, just a soft nudge.
            UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.4)
        }
    }

    /// Distinct from `fireHaptic` — an obstacle strike is an external event,
    /// not a kick-quality judgement, so it gets its own warning-style buzz
    /// regardless of which obstacle it was.
    private func fireObstacleHaptic(for _: ObstacleKind) {
        guard hapticsEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}
