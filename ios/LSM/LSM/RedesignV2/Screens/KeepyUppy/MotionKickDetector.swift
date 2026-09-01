import CoreMotion
import Foundation

/// Player intent behind a single detected kick — see `MotionKickDetector`.
/// Raw sensor readings are noisy on their own; the detector debounces them
/// into one discrete event per deliberate movement (docs/keepy-uppy-poc-scope.md
/// "Motion input model"). Aim/direction is no longer part of this — after
/// on-device testing, tilt-based aiming (device-frame `attitude.roll`) felt
/// imprecise, so boot positioning moved to touch-drag
/// (`KeepyUppyViewV2`/`KeepyUppyGame.footX`); motion now only supplies the
/// kick trigger + power.
struct KickInput {
    /// Normalised strength of the detected movement. 0 = no meaningful
    /// movement, 1 = maximum useful kick strength.
    let power: Double
    let timestamp: Date
}

/// Converts raw Core Motion readings into discrete `KickInput` events for the
/// keepy-uppy POC (docs/keepy-uppy-poc-scope.md).
///
/// Detects "upward" via the acceleration component along the true vertical
/// (opposite gravity), not raw device-frame `userAcceleration.y`. The
/// device-frame version only matches a real upward flick when the phone
/// happens to be held perfectly vertical with zero tilt — at any natural
/// holding angle, part of a genuine upward flick lands on the wrong axis,
/// and ordinary handling can trip the y-axis threshold for reasons that
/// have nothing to do with an upward motion. Projecting onto gravity fixes
/// both false negatives (missed flicks) and false positives (accidental
/// triggers) in one change, and needs no calibration step, unlike the old
/// roll-based aiming this replaced.
///
/// `triggerThreshold`/`resetThreshold`/the power scaling divisor below are
/// still POC defaults — expect to retune on a physical iPhone.
@MainActor
@Observable
final class MotionKickDetector {
    private(set) var livePower: Double = 0

    var sensitivity: Double = 1
    var onKick: ((KickInput) -> Void)?

    var isAvailable: Bool { motionManager.isDeviceMotionAvailable }

    private let motionManager = CMMotionManager()
    // Debounces one physical movement into one kick event — without this,
    // a single upward gesture would fire a kick on every sensor update
    // (60/sec) for as long as the acceleration stays above threshold.
    private var kickArmed = true

    func start() {
        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = 1.0 / 60.0
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            self.handle(motion)
        }
    }

    func stop() {
        motionManager.stopDeviceMotionUpdates()
        livePower = 0
    }

    private func handle(_ motion: CMDeviceMotion) {
        let a = motion.userAcceleration
        let g = motion.gravity
        // Dot product of userAcceleration with the (unit) gravity vector
        // gives the acceleration component pointing straight down in the
        // real world; negate for "straight up," regardless of how the
        // device itself is oriented.
        let verticalAcceleration = -(a.x * g.x + a.y * g.y + a.z * g.z)
        let adjustedAcceleration = max(0, verticalAcceleration) * sensitivity

        livePower = min(adjustedAcceleration / 1.2, 1)

        let triggerThreshold = 0.35
        let resetThreshold = 0.12

        if adjustedAcceleration > triggerThreshold, kickArmed {
            kickArmed = false
            onKick?(KickInput(power: livePower, timestamp: Date()))
        }

        // The player must finish (release) the current movement before
        // another kick can be detected.
        if adjustedAcceleration < resetThreshold {
            kickArmed = true
        }
    }
}
