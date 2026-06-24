import Foundation

/// The ordered stages of the "Show Me" walkthrough. Each *resting* step is a
/// state the user looks at (the real screens reflect it live); tapping the
/// primary button performs the data mutation that moves the game to the next
/// resting step (see `DemoWalkthroughManager.advance`). The data is added
/// progressively — never all up front — so the user watches the game being built.
enum DemoStep: Int, CaseIterable, Identifiable {
    case intro          // empty game, no players yet
    case players        // four sample players added
    case roundOpen      // round 1 opened on sample fixtures
    case picks          // every player assigned a team
    case results        // round 1 closed — eliminations worked out
    case done           // round 2 played out → a single winner; game complete

    var id: Int { rawValue }

    /// The next step in sequence (nil at the end).
    var next: DemoStep? { DemoStep(rawValue: rawValue + 1) }

    /// Short line for the persistent banner — always reminds the user they're in
    /// the demo and that data is being added step by step.
    var bannerText: String {
        AppString("Demo Mode — sample data is being added step by step")
    }

    /// Headline for the step explainer.
    var title: String {
        switch self {
        case .intro:     return AppString("An empty game")
        case .players:   return AppString("Players added")
        case .roundOpen: return AppString("Round 1 is open")
        case .picks:     return AppString("Everyone has a pick")
        case .results:   return AppString("Round 1 results are in")
        case .done:      return AppString("We have a winner!")
        }
    }

    /// Plain-language explanation of what just happened / what to look at.
    var detail: String {
        switch self {
        case .intro:
            return AppString("Demo Mode just created a brand-new game — no players, no rounds yet, exactly like starting for real. We'll build it up one step at a time.")
        case .players:
            return AppString("Four sample players joined the game. In the real app you'd pull these from your reusable player list.")
        case .roundOpen:
            return AppString("We opened the first round on four sample fixtures. Next, each player gets a team to survive with.")
        case .picks:
            return AppString("Every player has been assigned a team for round 1. Now we set the results and see who survives.")
        case .results:
            return AppString("Results set: a win, a win, a draw and a postponed match. The app worked out who's out — the draw is eliminated, but the postponed pick survives (a handy edge case to know).")
        case .done:
            return AppString("A second round narrowed the three survivors down to one. Sam is the last player standing — that's a full game, start to finish. Clear the demo, or keep exploring.")
        }
    }

    /// Label for the primary "advance" button. The final step keeps exploring
    /// (ends the walkthrough, leaving the finished game to poke around).
    var primaryButtonTitle: String {
        switch self {
        case .intro:     return AppString("Add players")
        case .players:   return AppString("Open round 1")
        case .roundOpen: return AppString("Assign picks")
        case .picks:     return AppString("Enter results")
        case .results:   return AppString("Play round 2")
        case .done:      return AppString("Keep exploring")
        }
    }

    /// `true` for the last step, where the primary button finishes rather than
    /// advancing.
    var isFinal: Bool { next == nil }
}
