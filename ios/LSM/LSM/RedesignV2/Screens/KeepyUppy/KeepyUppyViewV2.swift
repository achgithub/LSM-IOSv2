import Combine
import SwiftUI
import UIKit

/// Standalone POC screen for the keepy-uppy motion-control experiment
/// (docs/keepy-uppy-poc-scope.md). Reached only from a row in Settings' Help
/// panel (see `V2PreviewMenuView`'s `HomeHelpPanel`) — builds in Release too,
/// since motion feel can only be validated via TestFlight on a physical
/// device, not the Simulator. Deliberately outside the Games/LMS/Predictor/
/// Killer mode infrastructure,
/// since this doesn't create a `Game` and isn't a shipping mode. Purpose is
/// solely to validate whether the motion mechanic feels good before any
/// artwork/progression/monetisation work is considered.
struct KeepyUppyViewV2: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var game = KeepyUppyGame()
    @State private var motion = MotionKickDetector()

    @State private var motionEnabled = true
    @State private var hapticsEnabled = true
    @State private var sensitivity: Double = 1
    @AppStorage("keepyUppy.hasSeenSafetyMessage") private var hasSeenSafetyMessage = false

    @State private var lastTickDate: Date?
    @State private var showSafetyMessage = false
    @State private var isCalibrating = false
    @State private var calibrationSecondsLeft = 3
    @State private var flashFeedback: KickFeedback?
    @State private var tierBannerText: String?
    @State private var obstacleFlashActive = false

    private let calibrationTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(.systemBackground).ignoresSafeArea()
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
        .onAppear {
            motion.onKick = { [weak game = self.game] input in game?.applyKick(input) }
            motion.sensitivity = sensitivity
            game.motionActive = motionEnabled
            if motionEnabled { motion.start() }
        }
        .onDisappear { motion.stop() }
        .onChange(of: motionEnabled) { _, enabled in
            game.motionActive = enabled
            if enabled { motion.start() } else { motion.stop() }
        }
        .onChange(of: sensitivity) { _, newValue in motion.sensitivity = newValue }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                game.pause()
                motion.stop()
            } else if motionEnabled {
                motion.start()
            }
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
        .sheet(isPresented: $showSafetyMessage) { safetySheet }
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
                    if motionEnabled { game.footX = mappedFootX(from: motion.liveDirection) }
                    game.tick(deltaTime: CGFloat(delta))
                }
        }
    }

    /// Maps calibrated tilt (-1...1) to the boot's on-screen x — clamped
    /// short of the true edges so the boot sprite never renders half
    /// off-screen at full tilt.
    private func mappedFootX(from direction: Double) -> CGFloat {
        let clamped = max(-1, min(1, direction))
        return 0.5 + CGFloat(clamped) * 0.4
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

    /// The boot only renders while motion controls are on — with them off,
    /// `KeepyUppyGame.motionActive` makes every contact reachable
    /// regardless of position, so there's no meaningful boot position to
    /// show (see `applyKick`'s `motionActive` handling).
    @ViewBuilder
    private func foot(in size: CGSize) -> some View {
        if motionEnabled {
            let x = game.footX * size.width
            let y = game.footY * size.height
            let reachRadius = game.footReach * size.width
            ZStack {
                // Reach ring — a tuning/feedback aid showing how close the
                // ball needs to be, same spirit as the power/direction
                // meters (docs/keepy-uppy-poc-scope.md "development aids").
                Circle()
                    .stroke(V2Theme.accent.opacity(0.35), lineWidth: 1.5)
                    .frame(width: reachRadius * 2, height: reachRadius * 2)
                    .position(x: x, y: y)
                Text("🥾")
                    .font(.system(size: 40))
                    .position(x: x, y: y)
            }
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
            if motionEnabled {
                powerMeter
                    .frame(width: 120)
            }
            Spacer()
            VStack(alignment: .trailing) {
                Text("Best").font(.caption).foregroundStyle(.secondary)
                Text("\(game.bestScore)").font(.title2.bold())
            }
        }
    }

    private var powerMeter: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Power").font(.caption2).foregroundStyle(.secondary)
            ProgressView(value: motion.livePower)
                .tint(V2Theme.accent)
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

            DisclosureGroup("Motion settings") {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Motion controls", isOn: $motionEnabled)
                    Toggle("Haptics", isOn: $hapticsEnabled)
                    VStack(alignment: .leading) {
                        Text("Sensitivity: \(sensitivity, specifier: "%.1f")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Slider(value: $sensitivity, in: 0.5...2.0, step: 0.1)
                    }
                    Button {
                        startCalibration()
                    } label: {
                        Label(
                            isCalibrating ? "Hold still… \(calibrationSecondsLeft)" : "Calibrate neutral position",
                            systemImage: "location.north.line"
                        )
                    }
                    .disabled(!motionEnabled || isCalibrating)
                }
                .padding(.top, 6)
            }
        }
        .onReceive(calibrationTimer) { _ in
            guard isCalibrating else { return }
            if calibrationSecondsLeft > 1 {
                calibrationSecondsLeft -= 1
            } else {
                motion.calibrate()
                isCalibrating = false
            }
        }
    }

    private var startRestartButton: some View {
        Button(game.isGameOver ? "Restart" : "Start") {
            handleStartTapped()
        }
        .buttonStyle(.borderedProminent)
        .disabled(game.isRunning && !game.isGameOver)
    }

    private func handleStartTapped() {
        if motionEnabled, !hasSeenSafetyMessage {
            showSafetyMessage = true
        } else {
            game.start()
        }
    }

    private func startCalibration() {
        calibrationSecondsLeft = 3
        isCalibrating = true
    }

    // MARK: - Safety sheet

    private var safetySheet: some View {
        VStack(spacing: 20) {
            Image(systemName: "hand.raised.fill").font(.largeTitle).foregroundStyle(V2Theme.accent)
            Text("Before you start")
                .font(.title3.bold())
            Text("Hold your phone securely and use a short upward wrist movement. Make sure there is space around you.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Got it — Start") {
                hasSeenSafetyMessage = true
                showSafetyMessage = false
                game.start()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(32)
        .presentationDetents([.medium])
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
