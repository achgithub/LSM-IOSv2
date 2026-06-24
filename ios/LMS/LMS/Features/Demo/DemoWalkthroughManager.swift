import Foundation
import Observation
import SwiftData

/// Drives the "Show Me" walkthrough: owns the active step, the demo game's id, and
/// the start / advance / exit / clear transitions. It's the single source of truth
/// for "is the demo running" — `AdGate` reads `isActive` to suppress ads, the
/// banner renders from `currentStep`, and `GamesListView` follows `demoGameID` to
/// auto-open the game so the user watches it build.
///
/// All persistence goes through `DemoDataService` (and thus the real services);
/// this type only sequences the steps and tracks UI state.
@Observable @MainActor
final class DemoWalkthroughManager {
    static let shared = DemoWalkthroughManager()
    private init() {}

    /// True while the walkthrough is running. Drives the banner, the ad bypass,
    /// and the auto-navigation to the demo game.
    private(set) var isActive = false

    /// The current resting step the user is looking at.
    private(set) var currentStep: DemoStep = .intro

    /// The demo game's id, so views can find it in their `@Query` without the
    /// manager holding a SwiftData object across contexts.
    private(set) var demoGameID: UUID?

    // MARK: - Lifecycle

    /// Start (or restart) the demo. Clears any prior demo data first (duplicate
    /// protection, requirement: "if demo mode restarts, clear old demo records
    /// first"), seeds the local league cache, creates the empty game, and parks on
    /// the intro step.
    func start(context: ModelContext) {
        DemoDataService.clearDemoData(context: context)
        DemoDataService.seedLeagueCaches()
        let game = DemoDataService.createEmptyGame(context: context)
        demoGameID = game.id
        currentStep = .intro
        isActive = true
    }

    /// Perform the work that moves to the next step, then rest there. On the final
    /// step the primary button finishes instead (see `finish`).
    func advance(context: ModelContext) {
        guard isActive, let game = demoGame(in: context) else { return }
        switch currentStep {
        case .intro:
            DemoDataService.addPlayers(to: game, context: context)
        case .players:
            DemoDataService.openRound1(in: game, context: context)
        case .roundOpen:
            if let round = game.currentRound {
                DemoDataService.assignRound1Picks(game: game, round: round, context: context)
            }
        case .picks:
            if let round = game.currentRound {
                DemoDataService.closeRound1(game: game, round: round, context: context)
            }
        case .results:
            DemoDataService.playFinalRound(game: game, context: context)
        case .done:
            finish()
            return
        }
        if let next = currentStep.next { currentStep = next }
    }

    /// End the walkthrough but KEEP the finished demo game so the user can poke
    /// around it (the banner disappears; the game is still flagged demo data and
    /// can be removed later, or via Clear). Used by the final "Keep exploring".
    func finish() {
        isActive = false
        demoGameID = nil
        currentStep = .intro
    }

    /// Exit the demo: stop the walkthrough AND delete all demo records, returning
    /// the user to their normal (empty, on a fresh install) state.
    func exit(context: ModelContext) {
        DemoDataService.clearDemoData(context: context)
        isActive = false
        demoGameID = nil
        currentStep = .intro
    }

    /// Clear demo data and start over from an empty game — a "reset" that also
    /// satisfies the restart-clears-old-records requirement.
    func clearAndRestart(context: ModelContext) {
        start(context: context)
    }

    // MARK: - Lookup

    private func demoGame(in context: ModelContext) -> Game? {
        guard let id = demoGameID else { return nil }
        let descriptor = FetchDescriptor<Game>(predicate: #Predicate { $0.id == id })
        return try? context.fetch(descriptor).first
    }
}
