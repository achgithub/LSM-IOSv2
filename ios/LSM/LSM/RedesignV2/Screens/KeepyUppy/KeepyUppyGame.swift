import Foundation

/// Ball position/velocity in a screen-size-independent 0...1 coordinate
/// space — 0 is the left/top edge, 1 is the right/bottom edge — so the game
/// behaves the same on every device (docs/keepy-uppy-poc-scope.md "Ball
/// state and simple physics").
struct BallState {
    var x: CGFloat = 0.5
    var y: CGFloat = 0.2
    var velocityX: CGFloat = 0
    var velocityY: CGFloat = 0
}

/// Quality of a single contact attempt — drives both the on-screen flash and
/// which haptic fires (see `KeepyUppyViewV2`).
enum KickFeedback: Equatable {
    case perfect, good, earlyOrLate, miss
}

/// POC game engine for the keepy-uppy motion-control experiment
/// (docs/keepy-uppy-poc-scope.md) — self-contained physics/scoring, no
/// dependency on the Games/LMS/Predictor/Killer mode infrastructure this app
/// otherwise runs on. Driven every frame by `KeepyUppyViewV2`'s
/// `TimelineView` calling `tick(deltaTime:)`, not its own internal timer, so
/// it stays a plain, easily-testable state machine independent of the
/// render loop.
@MainActor
@Observable
final class KeepyUppyGame {
    private static let bestScoreKey = "keepyUppy.bestScore"

    var ball = BallState()
    var score = 0
    private(set) var bestScore = UserDefaults.standard.integer(forKey: KeepyUppyGame.bestScoreKey)
    var isRunning = false
    var isPaused = false
    var isGameOver = false
    /// Cleared by the view once it's fired the matching flash/haptic — see
    /// `KeepyUppyViewV2`'s `.onChange(of: game.lastFeedback)`.
    var lastFeedback: KickFeedback?

    /// The boot's horizontal position, 0...1 — set every frame by the view
    /// from calibrated device tilt (`MotionKickDetector.liveDirection`), not
    /// owned/animated by this engine. Vertical position is fixed (`footY`);
    /// only left/right is player-controlled.
    var footX: CGFloat = 0.5
    /// While `false` (motion controls off), a kick is always in reach
    /// regardless of `footX`/`footReach` — the Tap Kick fallback must stay
    /// a complete, always-works path per the design doc, not one gated on a
    /// foot the player has no way to steer.
    var motionActive = true

    // Tunables — POC defaults per the design doc; expect to retune on a
    // physical device alongside `MotionKickDetector`'s own thresholds.
    private let gravity: CGFloat = 1.25
    /// The boot's fixed height and how far the ball can be from it (in each
    /// axis) and still count as a touch. Deliberately narrow — a wide,
    /// full-width "contact zone" made every horizontal position equally
    /// valid, which didn't feel like actually having to reach the ball.
    let footY: CGFloat = 0.80
    let footReach: CGFloat = 0.11
    private let verticalTolerance: CGFloat = 0.07
    private let groundY: CGFloat = 0.94
    private let wallMargin: CGFloat = 0.06
    private let maxDeltaTime: CGFloat = 1.0 / 30.0

    func start() {
        ball = BallState()
        score = 0
        isGameOver = false
        isPaused = false
        isRunning = true
        lastFeedback = nil
    }

    func pause() { isPaused = true }
    func resume() { isPaused = false }

    /// Advances the ball one frame. `deltaTime` is clamped to
    /// `maxDeltaTime` so returning from the background (a large gap between
    /// frames) can't make the ball jump across the screen.
    func tick(deltaTime rawDeltaTime: CGFloat) {
        guard isRunning, !isPaused, !isGameOver else { return }
        let deltaTime = min(rawDeltaTime, maxDeltaTime)

        ball.velocityY += gravity * deltaTime
        ball.x += ball.velocityX * deltaTime
        ball.y += ball.velocityY * deltaTime

        // Soft side-wall rebounds keep the POC playable.
        if ball.x < wallMargin {
            ball.x = wallMargin
            ball.velocityX = abs(ball.velocityX) * 0.75
        } else if ball.x > 1 - wallMargin {
            ball.x = 1 - wallMargin
            ball.velocityX = -abs(ball.velocityX) * 0.75
        }

        if ball.y >= groundY {
            endGame()
        }
    }

    /// Valid only while the ball is descending, near the boot's height, and
    /// close enough horizontally to actually be reachable — the boot's own
    /// position (`footX`), not the swipe/tilt direction, is what has to
    /// line up with the ball. Where on the boot it lands (`contactOffset`
    /// below) determines the outgoing direction, the way an off-centre
    /// real kick would glance sideways rather than travel dead straight.
    func applyKick(_ kick: KickInput) {
        guard isRunning, !isPaused, !isGameOver else { return }
        guard ball.velocityY > 0 else { return }

        let verticalDistance = abs(ball.y - footY)
        let horizontalDistance = abs(ball.x - footX)
        let effectiveReach = motionActive ? footReach : 1.0

        guard verticalDistance <= verticalTolerance, horizontalDistance <= effectiveReach else {
            lastFeedback = .miss
            return
        }

        let timing = timingQuality(verticalDistance: verticalDistance, horizontalDistance: horizontalDistance, reach: effectiveReach)
        guard timing > 0 else {
            lastFeedback = .miss
            return
        }

        // Every valid gesture gets a minimum useful power so a gentle
        // movement never feels like the game ignored the player.
        let minimumUsefulPower = 0.62
        let effectivePower = minimumUsefulPower + (kick.power * 0.38)

        let verticalKickStrength: CGFloat = 1.05
        let horizontalKickStrength: CGFloat = 0.55

        // -1 (hit the left edge of the boot) ... 1 (right edge) — a dead
        // centre hit (0) goes straight up.
        let contactOffset = effectiveReach == 0 ? 0 : max(-1, min(1, (ball.x - footX) / effectiveReach))

        ball.velocityY = -verticalKickStrength * CGFloat(effectivePower) * timing
        ball.velocityX += contactOffset * horizontalKickStrength

        score += 1
        lastFeedback = timing >= 1.0 ? .perfect : (timing >= 0.84 ? .good : .earlyOrLate)
    }

    /// Tap-to-kick fallback — same `applyKick` path as motion input, so
    /// accessibility controls and motion controls stay mechanically
    /// consistent. Direction comes entirely from contact geometry now
    /// (`applyKick`'s `contactOffset`), so there's nothing left for the tap
    /// gesture itself to aim.
    func performTapKick() {
        applyKick(KickInput(power: 0.72, direction: 0, timestamp: Date()))
    }

    private func timingQuality(verticalDistance: CGFloat, horizontalDistance: CGFloat, reach: CGFloat) -> CGFloat {
        // How centred the contact was, on whichever axis is tighter —
        // dead-centre-of-the-boot at exactly boot height is the sweet spot.
        let normalized = max(verticalDistance / verticalTolerance, reach == 0 ? 0 : horizontalDistance / reach)
        switch normalized {
        case 0..<0.3: return 1.0        // Perfect
        case 0..<0.6: return 0.84       // Good
        case 0..<1.0: return 0.62       // Early or late / off-centre
        default: return 0               // Miss
        }
    }

    private func endGame() {
        isRunning = false
        isGameOver = true
        if score > bestScore {
            bestScore = score
            UserDefaults.standard.set(bestScore, forKey: KeepyUppyGame.bestScoreKey)
        }
    }
}
