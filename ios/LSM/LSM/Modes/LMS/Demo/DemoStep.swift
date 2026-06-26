import Foundation

/// The ordered stages of the "Show Me" guided demo. Each *resting* step is a
/// state the user looks at (the demo wizard's live preview reflects it); tapping
/// the highlighted primary button performs the data mutation that moves the game
/// to the next resting step (see `DemoWalkthroughManager.advance`). The data is
/// added progressively — never all up front — and both rounds are stepped through
/// so the user genuinely watches two rounds play out.
enum DemoStep: Int, CaseIterable, Identifiable {
    case intro          // empty game, no players yet
    case players        // four sample players added
    case round1Open     // round 1 opened on sample fixtures
    case round1Picks    // every player assigned a team for round 1
    case round1Results  // round 1 closed — eliminations worked out
    case resumeTip      // how to resume later (swipe right → wizard) — no data
    case round2Open     // round 2 opened for the survivors
    case round2Picks    // survivors assigned teams for round 2
    case done           // round 2 closed + winner declared; game complete

    var id: Int { rawValue }

    /// The next step in sequence (nil at the end).
    var next: DemoStep? { DemoStep(rawValue: rawValue + 1) }

    /// 1-based position and total, for a "Step 2 of 8" progress line.
    var displayIndex: Int { rawValue + 1 }
    static var count: Int { allCases.count }

    /// Short line for the demo banner — always reminds the user they're in the
    /// demo and that data is being added step by step.
    var bannerText: String {
        AppString("Demo Mode — sample data is being added step by step")
    }

    /// SF Symbol shown on the step card (mirrors the matching real wizard phase).
    var icon: String {
        switch self {
        case .intro:         return "trophy.fill"
        case .players:       return "person.2.fill"
        case .round1Open:    return "calendar.badge.plus"
        case .round1Picks:   return "checklist"
        case .round1Results: return "flag.checkered"
        case .resumeTip:     return "hand.draw"
        case .round2Open:    return "calendar.badge.plus"
        case .round2Picks:   return "checklist"
        case .done:          return "party.popper.fill"
        }
    }

    /// Headline for the step explainer.
    var title: String {
        switch self {
        case .intro:         return AppString("An empty game")
        case .players:       return AppString("Players added")
        case .round1Open:    return AppString("Round 1 is open")
        case .round1Picks:   return AppString("Everyone has a pick")
        case .round1Results: return AppString("Round 1 results are in")
        case .resumeTip:     return AppString("Carrying on later")
        case .round2Open:    return AppString("Round 2 is open")
        case .round2Picks:   return AppString("Round 2 picks are in")
        case .done:          return AppString("We have a winner!")
        }
    }

    /// Plain-language explanation of what just happened / what to look at.
    var detail: String {
        switch self {
        case .intro:
            // swiftlint:disable:next line_length
            return AppString("Demo Mode just created a brand-new game — no players, no rounds yet, exactly like starting for real. We'll build it up one step at a time.")
        case .players:
            return AppString("Four sample players joined the game. In the real app you'd pull these from your reusable player list.")
        case .round1Open:
            return AppString("We opened the first round on four sample fixtures. Next, each player gets a team to survive with.")
        case .round1Picks:
            return AppString("Every player has been assigned a team for round 1. Now we set the results and see who survives.")
        case .round1Results:
            // swiftlint:disable:next line_length
            return AppString("Results set: a win, a win, a draw and a postponed match. The draw is eliminated, but the postponed pick survives — a handy edge case. Three players go through.")
        case .resumeTip:
            // swiftlint:disable:next line_length
            return AppString("You don't have to finish in one go — your game is saved automatically. To pick it up later, go to the Games tab, swipe the game right, and tap the wizard to resume where you left off.")
        case .round2Open:
            return AppString("The three survivors carry forward into round 2, opened on a fresh set of fixtures.")
        case .round2Picks:
            return AppString("Each survivor has a team for round 2. One more set of results decides the game.")
        case .done:
            // swiftlint:disable:next line_length
            return AppString("Round 2 narrowed it to a single survivor — Sam is the last player standing. That's a full game, two rounds, start to finish. Clear the demo, or keep exploring.")
        }
    }

    /// Label for the highlighted primary button. The final step finishes (keeps
    /// the completed game to poke around).
    var primaryButtonTitle: String {
        switch self {
        case .intro:         return AppString("Add players")
        case .players:       return AppString("Open round 1")
        case .round1Open:    return AppString("Assign picks")
        case .round1Picks:   return AppString("Enter round 1 results")
        case .round1Results: return AppString("Got it")
        case .resumeTip:     return AppString("Open round 2")
        case .round2Open:    return AppString("Assign round 2 picks")
        case .round2Picks:   return AppString("Enter round 2 results")
        case .done:          return AppString("Keep exploring")
        }
    }

    /// `true` for the last step, where the primary button finishes rather than
    /// advancing.
    var isFinal: Bool { next == nil }
}
