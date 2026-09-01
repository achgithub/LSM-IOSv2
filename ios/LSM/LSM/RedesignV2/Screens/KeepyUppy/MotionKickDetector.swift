import CoreMotion
import Foundation

/// Player intent behind a single detected kick — see `MotionKickDetector`.
/// Raw sensor readings are noisy on their own; the detector debounces them
/// into one discrete event per deliberate movement (docs/keepy-uppy-poc-scope.md
/// "Motion input model").
struct KickInput {
    /// Normalised strength of the detected movement. 0 = no meaningful
    /// movement, 1 = maximum useful kick strength.
    let power: Double
    /// Horizontal aim from calibrated device tilt. -1 = fully left,
    /// 0 = straight, 1 = fully right.
    let direction: Double
    let timestamp: Date
}

/// Converts raw Core Motion readings into discrete `KickInput` events for the
/// keepy-uppy POC (docs/keepy-uppy-poc-scope.md). `triggerThreshold`/
/// `resetThreshold`/the power-and-direction scaling divisors below are POC
/// defaults only — the design doc is explicit that these need retuning on a
/// physical iPhone; the Simulator can't validate whether the movement feels
/// natural, only that events fire at all.
@MainActor
@Observable
final class MotionKickDetector {
    private(set) var livePower: Double = 0
    private(set) var liveDirection: Double = 0

    var sensitivity: Double = 1
    var onKick: ((KickInput) -> Void)?

    var isAvailable: Bool { motionManager.isDeviceMotionAvailable }

    private let motionManager = CMMotionManager()
    private var neutralRoll = 0.0
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

    func calibrate() {
        neutralRoll = motionManager.deviceMotion?.attitude.roll ?? 0
    }

    func stop() {
        motionManager.stopDeviceMotionUpdates()
        livePower = 0
        liveDirection = 0
    }

    private func handle(_ motion: CMDeviceMotion) {
        let upwardAcceleration = max(0, motion.userAcceleration.y)
        let adjustedAcceleration = upwardAcceleration * sensitivity
        let adjustedRoll = motion.attitude.roll - neutralRoll

        livePower = min(adjustedAcceleration / 1.2, 1)
        liveDirection = max(-1, min(adjustedRoll / 0.45, 1))

        let triggerThreshold = 0.35
        let resetThreshold = 0.12

        if adjustedAcceleration > triggerThreshold, kickArmed {
            kickArmed = false
            onKick?(KickInput(power: livePower, direction: liveDirection, timestamp: Date()))
        }

        // The player must finish (release) the current movement before
        // another kick can be detected.
        if adjustedAcceleration < resetThreshold {
            kickArmed = true
        }
    }
}
