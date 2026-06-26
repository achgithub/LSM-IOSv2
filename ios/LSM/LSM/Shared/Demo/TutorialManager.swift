import SwiftUI
import SwiftData

/// Central state for the "See How It Works" tutorial. Tracks the current step,
/// the highlight frame reported by each tagged control, and the demo game ID.
/// `isActive` is read by `AdGate` to bypass rewarded ads during the tutorial.
@Observable @MainActor
final class TutorialManager {
    static let shared = TutorialManager()
    private init() {}

    private(set) var isActive = false
    private(set) var tutorialGameID: UUID?
    private(set) var currentStep: TutorialStep = .lmsWelcome

    /// Frame registry: each `.tutorialAnchor(id:)` control reports its position
    /// here so the dim overlay can cut a hole in the right place.
    var frames: [String: CGRect] = [:]

    var activeFrame: CGRect? {
        guard let id = currentStep.anchorId else { return nil }
        return frames[id]
    }

    func begin(gameID: UUID, mode: GameMode) {
        tutorialGameID = gameID
        isActive = true
        currentStep = mode == .lms ? .lmsWelcome : .predictorWelcome
    }

    func advance(to step: TutorialStep) {
        guard isActive else { return }
        withAnimation(.spring(duration: 0.3)) { currentStep = step }
    }

    func setFrame(_ frame: CGRect, id: String) {
        frames[id] = frame
    }

    func end(context: ModelContext) {
        TutorialDataService.clearTutorialData(context: context)
        isActive = false
        tutorialGameID = nil
        frames.removeAll()
    }
}
