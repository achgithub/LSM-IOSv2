import Combine
import SwiftUI
import UIKit

/// Standalone POC screen for the keepy-uppy motion-control experiment
/// (docs/keepy-uppy-poc-scope.md). Reached only from Settings' Help panel
/// behind a `#if DEBUG` row (see `V2PreviewMenuView`'s `HomeHelpPanel`) —
/// deliberately outside the Games/LMS/Predictor/Killer mode infrastructure,
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

    private let calibrationTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(.systemBackground).ignoresSafeArea()
                tickDriver
                contactZone(in: geo.size)
                ball(in: geo.size)
                feedbackFlash
                VStack(spacing: 16) {
                    hud
                    Spacer()
                    if game.isGameOver {
                        gameOverPanel
                    }
                    controls
                }
                .padding()
            }
        }
        .navigationTitle("Keepy-Uppy (POC)")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            motion.onKick = { [weak game = self.game] input in game?.applyKick(input) }
            motion.sensitivity = sensitivity
            if motionEnabled { motion.start() }
        }
        .onDisappear { motion.stop() }
        .onChange(of: motionEnabled) { _, enabled in
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
                    game.tick(deltaTime: CGFloat(delta))
                }
        }
    }

    // MARK: - Field

    private func contactZone(in size: CGSize) -> some View {
        let start = game.contactZoneRange.lowerBound * size.height
        let end = game.contactZoneRange.upperBound * size.height
        let perfect = game.perfectContactPoint * size.height
        return ZStack(alignment: .top) {
            Rectangle()
                .fill(V2Theme.accent.opacity(0.12))
                .frame(height: end - start)
                .position(x: size.width / 2, y: (start + end) / 2)
            Rectangle()
                .fill(V2Theme.accent.opacity(0.6))
                .frame(height: 2)
                .position(x: size.width / 2, y: perfect)
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
                VStack(spacing: 4) {
                    powerMeter
                    directionIndicator
                }
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

    private var directionIndicator: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Direction").font(.caption2).foregroundStyle(.secondary)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.2)).frame(height: 6)
                    Circle()
                        .fill(V2Theme.accent)
                        .frame(width: 10, height: 10)
                        .offset(x: (geo.size.width - 10) * CGFloat((motion.liveDirection + 1) / 2))
                }
            }
            .frame(height: 10)
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
}
