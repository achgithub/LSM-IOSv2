import Foundation

/// Every guided step for both tutorial modes. The `anchorId` matches a
/// `.tutorialAnchor(id:)` tag placed on a real app control; nil means
/// no specific control — the full-screen dim shows instead.
enum TutorialStep: Equatable {

    // MARK: - LMS (2 full rounds → Sam wins)
    case lmsWelcome
    case lmsPlayers
    case lmsOpenRound1
    case lmsEnterPicks1
    case lmsEnterResults1
    case lmsShareRound1
    case lmsOpenRound2
    case lmsEnterPicks2
    case lmsEnterResults2
    case lmsWinner

    // MARK: - Predictor (1 matchday)
    case predictorWelcome
    case predictorPlayers
    case predictorOpenRound
    case predictorEnterPredictions
    case predictorCloseRound
    case predictorShare

    // MARK: - Anchor ID (matches .tutorialAnchor tags in real views)

    var anchorId: String? {
        switch self {
        case .lmsPlayers:                     return "lms.addPlayers"
        case .lmsOpenRound1, .lmsOpenRound2:  return "lms.openRound"
        case .lmsEnterPicks1, .lmsEnterPicks2: return "lms.enterPicks"
        case .lmsEnterResults1, .lmsEnterResults2: return "lms.enterResults"
        case .lmsShareRound1, .lmsWinner:     return "lms.shareResults"
        case .predictorPlayers:               return "pred.addPlayers"
        case .predictorOpenRound:             return "pred.openRound"
        case .predictorEnterPredictions:      return "pred.enterPredictions"
        case .predictorCloseRound:            return "pred.enterResults"
        case .predictorShare:                 return "pred.shareResults"
        default:                              return nil
        }
    }

    // MARK: - Advancement

    /// Informational steps need the user to tap "Next" — all others auto-advance
    /// when the game's state satisfies the completion predicate.
    var requiresManualAdvance: Bool {
        switch self {
        case .lmsWelcome, .lmsPlayers, .lmsShareRound1, .lmsWinner,
             .predictorWelcome, .predictorPlayers, .predictorShare:
            return true
        default:
            return false
        }
    }

    var isFinalStep: Bool { self == .lmsWinner || self == .predictorShare }

    // MARK: - Copy

    var title: String {
        switch self {
        case .lmsWelcome:                return AppString("Last Man Standing")
        case .lmsPlayers:                return AppString("Players are in")
        case .lmsOpenRound1:             return AppString("Open Round 1")
        case .lmsEnterPicks1:            return AppString("Assign picks")
        case .lmsEnterResults1:          return AppString("Enter results")
        case .lmsShareRound1:            return AppString("Round 1 done")
        case .lmsOpenRound2:             return AppString("Open Round 2")
        case .lmsEnterPicks2:            return AppString("Assign Round 2 picks")
        case .lmsEnterResults2:          return AppString("Enter Round 2 results")
        case .lmsWinner:                 return AppString("We have a winner!")
        case .predictorWelcome:          return AppString("Predictor")
        case .predictorPlayers:          return AppString("Players are in")
        case .predictorOpenRound:        return AppString("Open Matchday 1")
        case .predictorEnterPredictions: return AppString("Enter predictions")
        case .predictorCloseRound:       return AppString("Enter results & close")
        case .predictorShare:            return AppString("Leaderboard is live")
        }
    }

    var detail: String {
        switch self {
        case .lmsWelcome:
            return AppString("Each round every player picks one team. Pick a loser — you're out. Last one standing wins. Two full rounds, then we'll declare the winner.")
        case .lmsPlayers:
            return AppString("4 tutorial players are ready. In your real game, tap Add Players to invite your group.")
        case .lmsOpenRound1:
            return AppString("Tap Open Round. Tutorial fixtures are already loaded — just tap Open in the sheet.")
        case .lmsEnterPicks1:
            return AppString("Tap Enter Picks. Each player's pick is pre-set for the tutorial — tap Done to save them.")
        case .lmsEnterResults1:
            return AppString("Tap Enter Results. Scores are pre-filled — tap Close Round to eliminate and advance.")
        case .lmsShareRound1:
            return AppString("One player drawn, one postponed (survives). Three go through. Share the round card, then tap Next for Round 2.")
        case .lmsOpenRound2:
            return AppString("Three survive — open Round 2. Same flow: tap Open Round, picks auto-fill, then enter results.")
        case .lmsEnterPicks2:
            return AppString("Tap Enter Picks for Round 2. Picks are pre-set — tap Done.")
        case .lmsEnterResults2:
            return AppString("Tap Enter Results to close Round 2 and find the Last Man Standing.")
        case .lmsWinner:
            return AppString("Sam picked winners in both rounds — Last Man Standing! Share the results card with your group, then tap Finish.")
        case .predictorWelcome:
            return AppString("Predict the score for every fixture. Points for the correct result, goal difference, or an exact score. One matchday, four fixtures.")
        case .predictorPlayers:
            return AppString("4 tutorial players ready. In your real game, tap Add Players to invite your group.")
        case .predictorOpenRound:
            return AppString("Tap Open Matchday. Tutorial fixtures are pre-loaded — tap Open in the sheet.")
        case .predictorEnterPredictions:
            return AppString("Tap Enter Predictions. Three players are pre-filled. Enter your own score for the first fixture, then tap Done.")
        case .predictorCloseRound:
            return AppString("Full time — tap Enter Results. Scores are pre-filled. Tap Close Round to calculate points.")
        case .predictorShare:
            return AppString("Sam topped the leaderboard. Share the weekly results card with your group, then tap Finish.")
        }
    }

    var nextButtonTitle: String {
        switch self {
        case .lmsWelcome, .predictorWelcome:  return AppString("Let's go")
        case .lmsPlayers, .predictorPlayers:  return AppString("Got it")
        case .lmsShareRound1:                 return AppString("Round 2 →")
        case .lmsWinner, .predictorShare:     return AppString("Finish")
        default:                              return AppString("Next")
        }
    }

    var skipButtonTitle: String {
        switch self {
        case .lmsOpenRound1, .lmsOpenRound2, .predictorOpenRound:   return AppString("Open for me")
        case .lmsEnterPicks1, .lmsEnterPicks2, .predictorEnterPredictions: return AppString("Fill for me")
        case .lmsEnterResults1, .lmsEnterResults2, .predictorCloseRound:   return AppString("Close for me")
        default:                                                      return AppString("Skip")
        }
    }
}
