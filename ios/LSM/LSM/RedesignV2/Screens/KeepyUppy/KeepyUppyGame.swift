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

/// A flying hazard that knocks the ball off course on contact — see
/// `KeepyUppyGame.updateObstacles`. Seagull flies a straight line; drone
/// zig-zags (a sine wave riding on top of its straight-line travel).
enum ObstacleKind: Equatable {
    case seagull, drone
}

/// One obstacle in flight. `x`/`baseY` are in the same 0...1 space as
/// `BallState`; `elapsed` is simulation time since spawn (not wall-clock —
/// see `KeepyUppyGame.tick`), so a paused game can't cause a drone to jump
/// along its sine path when resumed.
struct Obstacle: Identifiable, Equatable {
    let id = UUID()
    let kind: ObstacleKind
    var x: CGFloat
    let baseY: CGFloat
    let velocityX: CGFloat
    var elapsed: CGFloat = 0
}

/// Fired once per obstacle collision — cleared by the view after it fires
/// the haptic, same pattern as `KeepyUppyGame.lastFeedback`.
struct ObstacleHitEvent: Equatable {
    let kind: ObstacleKind
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

    /// Signed lateral wind force currently applied to the ball, roughly
    /// -1 (strong left) ... 1 (strong right) — see `updateWind`. Smoothed
    /// toward `windTarget` rather than snapping, so the windsock visibly
    /// swings before the ball actually feels the new gust (telegraphing,
    /// not a surprise shove).
    private(set) var windSpeed: CGFloat = 0
    /// True once score has crossed into a wind tier — the windsock only
    /// renders while this is true (docs: "starts easy, no wind").
    var isWindActive: Bool { Self.windTier(for: score).maxStrength > 0 }
    /// Set once per tier crossing, cleared by the view after it shows the
    /// banner/haptic — same pattern as `lastFeedback`.
    var tierAnnouncement: String?

    private var windTarget: CGFloat = 0
    private var windGustTimer: CGFloat = 0
    private var lastAnnouncedTier = 0

    /// Seagulls/drones currently in flight — see `updateObstacles`. Public
    /// (read-only in spirit, but `@Observable` needs it settable) so the
    /// view can render each one at `obstacleY(_:)`.
    var obstacles: [Obstacle] = []
    /// Set on every collision, cleared by the view after it fires the
    /// haptic — same pattern as `lastFeedback`/`tierAnnouncement`.
    var obstacleHitEvent: ObstacleHitEvent?

    private var seagullSpawnTimer: CGFloat = 0
    private var droneSpawnTimer: CGFloat = 0

    /// The boot's horizontal position, 0...1 — set by the view from a touch
    /// drag on the field, not owned/animated by this engine. Vertical
    /// position is fixed (`footY`); only left/right is player-controlled.
    /// Was tilt-driven; moved to touch after on-device testing found
    /// roll-based aiming imprecise, and touch is simply the more direct
    /// mapping — where your thumb is is where the boot is.
    var footX: CGFloat = 0.5

    /// A flick (or Tap Kick) doesn't move the ball by itself any more — it
    /// only arms a short-lived request that `updateBootContact` consults
    /// the moment the ball actually touches the boot. This lets contact
    /// with the boot always do *something* physical (see
    /// `updateBootContact`'s passive-bounce path) instead of the ball
    /// silently falling through whenever a kick attempt and the ball's
    /// arrival don't land in the exact same instant.
    private var pendingKickPower: Double?
    private var pendingKickAge: CGFloat = 0
    /// How long a flick/tap stays "armed" waiting for the ball to actually
    /// arrive at the boot before it's considered too late.
    private let kickRequestWindow: CGFloat = 0.35

    // Tunables — POC defaults; expect to retune on a physical device.
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
    /// How strongly `windSpeed` actually pushes the ball each tick — a
    /// separate scale from `windSpeed`'s own -1...1 range so the two can be
    /// tuned independently (visual vane swing vs. felt physics effect).
    private let windAcceleration: CGFloat = 1.6
    /// How quickly `windSpeed` chases `windTarget` — lower reads as more
    /// "gust arriving," higher as "instant shove." Not proportional to
    /// deltaTime directly since this is a per-second chase rate, not a
    /// fixed-per-frame step.
    private let windSmoothingRate: CGFloat = 0.5
    /// A touch/no-kick-request bounce off the boot — weaker than any scored
    /// kick, so it's clearly the "the boot is just solid" case, not a
    /// substitute for actually timing a flick.
    private let passiveBounceStrength: CGFloat = 0.5
    private let passiveHorizontalStrength: CGFloat = 0.25
    private let verticalKickStrength: CGFloat = 1.05
    private let horizontalKickStrength: CGFloat = 0.55

    /// One entry of the score-based difficulty ladder (every 20 points, per
    /// Andrew) — kept as plain data so `updateWind`/`isWindActive` don't
    /// duplicate the score thresholds. `isGusty` false means "steady": one
    /// constant-strength push rather than a randomised gust cycle.
    private struct WindTier {
        let maxStrength: CGFloat
        let isGusty: Bool
        let announcement: String?
    }

    private static func windTier(for score: Int) -> WindTier {
        switch score {
        case ..<20:
            return WindTier(maxStrength: 0, isGusty: false, announcement: nil)
        case 20..<40:
            return WindTier(maxStrength: 0.18, isGusty: false, announcement: "Wind picking up")
        case 40..<60:
            return WindTier(maxStrength: 0.30, isGusty: true, announcement: "Gusts incoming")
        case 60..<80:
            return WindTier(maxStrength: 0.45, isGusty: true, announcement: "Strong gusts")
        default:
            return WindTier(maxStrength: 0.60, isGusty: true, announcement: "Full storm")
        }
    }

    /// Index of the tier `score` falls in — only used to detect a
    /// *crossing* (see `checkTierMilestone`), not for any wind math itself.
    private static func windTierIndex(for score: Int) -> Int {
        switch score {
        case ..<20: return 0
        case 20..<40: return 1
        case 40..<60: return 2
        case 60..<80: return 3
        default: return 4
        }
    }

    /// Obstacle side of the same every-20 ladder, continuing past wind's
    /// top tier — per Andrew: seagulls start at one, slow, and build to
    /// three, fast; the drone (zig-zag) arrives after that, starting slow
    /// and getting faster the longer the run continues (scored
    /// continuously past its intro score rather than in further discrete
    /// steps, so a very long run keeps getting harder without needing an
    /// ever-growing tier table).
    private struct ObstacleTier {
        let maxSeagulls: Int
        let seagullSpeed: CGFloat
        let droneEnabled: Bool
        let droneSpeed: CGFloat
    }

    private static let droneIntroScore = 120
    private static let droneMaxSpeed: CGFloat = 0.42

    private static func obstacleTier(for score: Int) -> ObstacleTier {
        let maxSeagulls: Int
        let seagullSpeed: CGFloat
        switch score {
        case ..<60:
            maxSeagulls = 0; seagullSpeed = 0
        case 60..<80:
            maxSeagulls = 1; seagullSpeed = 0.14
        case 80..<100:
            maxSeagulls = 2; seagullSpeed = 0.20
        default:
            maxSeagulls = 3; seagullSpeed = 0.28
        }

        let droneEnabled = score >= droneIntroScore
        let droneSpeed: CGFloat = droneEnabled
            ? min(droneMaxSpeed, 0.16 + CGFloat(score - droneIntroScore) * 0.0015)
            : 0

        return ObstacleTier(maxSeagulls: maxSeagulls, seagullSpeed: seagullSpeed, droneEnabled: droneEnabled, droneSpeed: droneSpeed)
    }

    func start() {
        ball = BallState()
        score = 0
        isGameOver = false
        isPaused = false
        isRunning = true
        lastFeedback = nil
        windSpeed = 0
        windTarget = 0
        windGustTimer = 0
        lastAnnouncedTier = 0
        tierAnnouncement = nil
        obstacles = []
        obstacleHitEvent = nil
        seagullSpawnTimer = 0
        droneSpawnTimer = 0
        pendingKickPower = nil
        pendingKickAge = 0
    }

    func pause() { isPaused = true }
    func resume() { isPaused = false }

    /// Advances the ball one frame. `deltaTime` is clamped to
    /// `maxDeltaTime` so returning from the background (a large gap between
    /// frames) can't make the ball jump across the screen.
    func tick(deltaTime rawDeltaTime: CGFloat) {
        guard isRunning, !isPaused, !isGameOver else { return }
        let deltaTime = min(rawDeltaTime, maxDeltaTime)

        updateWind(deltaTime: deltaTime)
        ageKickRequest(deltaTime: deltaTime)

        ball.velocityY += gravity * deltaTime
        ball.velocityX += windSpeed * windAcceleration * deltaTime
        ball.x += ball.velocityX * deltaTime
        ball.y += ball.velocityY * deltaTime

        updateBootContact()
        updateObstacles(deltaTime: deltaTime)

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

    /// Arms a kick attempt (from a flick or Tap Kick) without touching the
    /// ball directly — `updateBootContact` is the only place that actually
    /// moves the ball on contact, so there's exactly one code path to
    /// reason about instead of two systems racing to decide what happens
    /// when the ball reaches the boot.
    func requestKick(power: Double) {
        guard isRunning, !isPaused, !isGameOver else { return }
        pendingKickPower = power
        pendingKickAge = 0
    }

    private func ageKickRequest(deltaTime: CGFloat) {
        guard pendingKickPower != nil else { return }
        pendingKickAge += deltaTime
        if pendingKickAge > kickRequestWindow {
            pendingKickPower = nil
        }
    }

    /// The boot is a solid object: any time the descending ball is close
    /// enough (see `footReach`/`verticalTolerance`), *something* happens —
    /// either a real, scored kick if a flick/tap was armed recently enough
    /// (`pendingKickPower`), or a weaker passive bounce if not. Either way
    /// the outgoing velocity always goes negative, which is what keeps this
    /// from re-firing every frame of continued overlap — the `velocityY > 0`
    /// guard below naturally won't pass again until the ball has looped
    /// back down for a new touch.
    private func updateBootContact() {
        guard ball.velocityY > 0 else { return }

        let verticalDistance = abs(ball.y - footY)
        let horizontalDistance = abs(ball.x - footX)
        guard verticalDistance <= verticalTolerance, horizontalDistance <= footReach else { return }

        // -1 (touched the left edge of the boot) ... 1 (right edge) — a
        // dead-centre touch goes straight up, off-centre glances sideways,
        // the way a real touch would.
        let contactOffset = footReach == 0 ? 0 : max(-1, min(1, (ball.x - footX) / footReach))

        guard let power = pendingKickPower else {
            ball.velocityY = -passiveBounceStrength
            ball.velocityX += contactOffset * passiveHorizontalStrength
            return
        }
        pendingKickPower = nil

        let timing = timingQuality(verticalDistance: verticalDistance, horizontalDistance: horizontalDistance, reach: footReach)
        guard timing > 0 else {
            // Attempted, but badly mistimed — still just a passive bounce,
            // not a wasted touch that lets the ball fall straight through.
            ball.velocityY = -passiveBounceStrength
            ball.velocityX += contactOffset * passiveHorizontalStrength
            lastFeedback = .miss
            return
        }

        // Every valid gesture gets a minimum useful power so a gentle
        // movement never feels like the game ignored the player.
        let minimumUsefulPower = 0.62
        let effectivePower = minimumUsefulPower + (power * 0.38)

        ball.velocityY = -verticalKickStrength * CGFloat(effectivePower) * timing
        ball.velocityX += contactOffset * horizontalKickStrength

        score += 1
        lastFeedback = timing >= 1.0 ? .perfect : (timing >= 0.84 ? .good : .earlyOrLate)
        checkTierMilestone()
    }

    /// Steps `windSpeed` toward whatever this score's tier calls for.
    /// "Steady" tiers pick one strength+direction and hold it; "gusty"
    /// tiers re-roll a new target every few seconds. Either way `windSpeed`
    /// eases toward `windTarget` rather than jumping — see
    /// `windSmoothingRate`.
    private func updateWind(deltaTime: CGFloat) {
        let tier = Self.windTier(for: score)

        guard tier.maxStrength > 0 else {
            windTarget = 0
            windSpeed = 0
            windGustTimer = 0
            return
        }

        if tier.isGusty {
            windGustTimer -= deltaTime
            if windGustTimer <= 0 {
                windGustTimer = CGFloat.random(in: 3...6)
                windTarget = CGFloat.random(in: -tier.maxStrength...tier.maxStrength)
            }
        } else if windTarget == 0 {
            // Steady tier, not yet rolled — pick one direction and hold it
            // for the rest of the tier.
            windTarget = Bool.random() ? tier.maxStrength : -tier.maxStrength
        }

        let chase = min(1, windSmoothingRate * deltaTime)
        windSpeed += (windTarget - windSpeed) * chase
    }

    private func checkTierMilestone() {
        let tier = Self.windTierIndex(for: score)
        guard tier != lastAnnouncedTier else { return }
        lastAnnouncedTier = tier
        tierAnnouncement = Self.windTier(for: score).announcement
    }

    /// The obstacle's actual render/collision height — a seagull flies a
    /// straight line at its spawn height; a drone's height rides a sine
    /// wave on top of that (the "zig-zag"), driven by simulation time
    /// elapsed since it spawned, not wall-clock time.
    func obstacleY(_ obstacle: Obstacle) -> CGFloat {
        switch obstacle.kind {
        case .seagull:
            return obstacle.baseY
        case .drone:
            let amplitude: CGFloat = 0.12
            let frequency: CGFloat = 3.2
            return obstacle.baseY + amplitude * sin(obstacle.elapsed * frequency)
        }
    }

    /// Spawns due obstacles, advances everything in flight, and knocks the
    /// ball on any contact. Runs every tick regardless of tier — the tier
    /// tables above are what actually gate whether anything spawns.
    private func updateObstacles(deltaTime: CGFloat) {
        let tier = Self.obstacleTier(for: score)

        if tier.maxSeagulls > 0 {
            seagullSpawnTimer -= deltaTime
            let activeSeagulls = obstacles.filter { $0.kind == .seagull }.count
            if seagullSpawnTimer <= 0, activeSeagulls < tier.maxSeagulls {
                spawnSeagull(speed: tier.seagullSpeed)
                seagullSpawnTimer = CGFloat.random(in: 2.5...4.5)
            }
        }

        if tier.droneEnabled {
            droneSpawnTimer -= deltaTime
            let droneActive = obstacles.contains { $0.kind == .drone }
            if droneSpawnTimer <= 0, !droneActive {
                spawnDrone(speed: tier.droneSpeed)
                droneSpawnTimer = CGFloat.random(in: 5...8)
            }
        }

        for i in obstacles.indices {
            obstacles[i].elapsed += deltaTime
            obstacles[i].x += obstacles[i].velocityX * deltaTime
        }

        let hitRadius: CGFloat = 0.07
        var hitIndices: [Int] = []
        for (i, obstacle) in obstacles.enumerated() {
            let dx = ball.x - obstacle.x
            let dy = ball.y - obstacleY(obstacle)
            if dx * dx + dy * dy <= hitRadius * hitRadius {
                hitIndices.append(i)
            }
        }
        for i in hitIndices.reversed() {
            applyKnock(from: obstacles[i])
            obstacles.remove(at: i)
        }

        // Off-screen in either direction — despawn.
        obstacles.removeAll { $0.x < -0.15 || $0.x > 1.15 }
    }

    /// A hit is a shove, not an instant fail — it changes the ball's
    /// trajectory (in the direction the obstacle was travelling, plus a
    /// downward push that makes the next touch harder) and lets physics
    /// carry the consequence, rather than ending the game on contact.
    private func applyKnock(from obstacle: Obstacle) {
        let knockStrength: CGFloat = 0.9
        ball.velocityX += (obstacle.velocityX >= 0 ? 1 : -1) * knockStrength
        ball.velocityY += 0.4
        obstacleHitEvent = ObstacleHitEvent(kind: obstacle.kind)
    }

    private func spawnSeagull(speed: CGFloat) {
        let fromLeft = Bool.random()
        obstacles.append(Obstacle(
            kind: .seagull,
            x: fromLeft ? -0.08 : 1.08,
            baseY: CGFloat.random(in: 0.18...0.55),
            velocityX: fromLeft ? speed : -speed
        ))
    }

    private func spawnDrone(speed: CGFloat) {
        let fromLeft = Bool.random()
        obstacles.append(Obstacle(
            kind: .drone,
            x: fromLeft ? -0.08 : 1.08,
            baseY: CGFloat.random(in: 0.20...0.5),
            velocityX: fromLeft ? speed : -speed
        ))
    }

    /// Tap-to-kick fallback — same `requestKick`/`updateBootContact` path
    /// as motion input, so accessibility controls and motion controls stay
    /// mechanically consistent. Direction comes entirely from contact
    /// geometry (`updateBootContact`'s `contactOffset`), so there's nothing
    /// left for the tap gesture itself to aim.
    func performTapKick() {
        requestKick(power: 0.72)
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
