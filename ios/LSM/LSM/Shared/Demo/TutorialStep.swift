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
        case .lmsWelcome:                return "Last Man Standing"
        case .lmsPlayers:                return "Players are in"
        case .lmsOpenRound1:             return "Open Round 1"
        case .lmsEnterPicks1:            return "Assign picks"
        case .lmsEnterResults1:          return "Enter results"
        case .lmsShareRound1:            return "Round 1 done"
        case .lmsOpenRound2:             return "Open Round 2"
        case .lmsEnterPicks2:            return "Assign Round 2 picks"
        case .lmsEnterResults2:          return "Enter Round 2 results"
        case .lmsWinner:                 return "We have a winner!"
        case .predictorWelcome:          return "Predictor"
        case .predictorPlayers:          return "Players are in"
        case .predictorOpenRound:        return "Open Matchday 1"
        case .predictorEnterPredictions: return "Enter predictions"
        case .predictorCloseRound:       return "Enter results & close"
        case .predictorShare:            return "Leaderboard is live"
        }
    }

    var detail: String {
        switch self {
        case .lmsWelcome:
            return "Each round every player picks one team. Pick a loser — you're out. Last one standing wins. Two full rounds, then we'll declare the winner."
        case .lmsPlayers:
            return "4 tutorial players are ready. In your real game, tap Add Players to invite your group."
        case .lmsOpenRound1:
            return "Tap Open Round. Tutorial fixtures are already loaded — just tap Open in the sheet."
        case .lmsEnterPicks1:
            return "Tap Enter Picks. Each player's pick is pre-set for the tutorial — tap Done to save them."
        case .lmsEnterResults1:
            return "Tap Enter Results. Scores are pre-filled — tap Close Round to eliminate and advance."
        case .lmsShareRound1:
            return "One player drawn, one postponed (survives). Three go through. Share the round card, then tap Next for Round 2."
        case .lmsOpenRound2:
            return "Three survive — open Round 2. Same flow: tap Open Round, picks auto-fill, then enter results."
        case .lmsEnterPicks2:
            return "Tap Enter Picks for Round 2. Picks are pre-set — tap Done."
        case .lmsEnterResults2:
            return "Tap Enter Results to close Round 2 and find the Last Man Standing."
        case .lmsWinner:
            return "Sam picked winners in both rounds — Last Man Standing! Share the results card with your group, then tap Finish."
        case .predictorWelcome:
            return "Predict the score for every fixture. Points for the correct result, goal difference, or an exact score. One matchday, four fixtures."
        case .predictorPlayers:
            return "4 tutorial players ready. In your real game, tap Add Players to invite your group."
        case .predictorOpenRound:
            return "Tap Open Matchday. Tutorial fixtures are pre-loaded — tap Open in the sheet."
        case .predictorEnterPredictions:
            return "Tap Enter Predictions. Three players are pre-filled. Enter your own score for the first fixture, then tap Done."
        case .predictorCloseRound:
            return "Full time — tap Enter Results. Scores are pre-filled. Tap Close Round to calculate points."
        case .predictorShare:
            return "Sam topped the leaderboard. Share the weekly results card with your group, then tap Finish."
        }
    }

    var nextButtonTitle: String {
        switch self {
        case .lmsWelcome, .predictorWelcome:  return "Let's go"
        case .lmsPlayers, .predictorPlayers:  return "Got it"
        case .lmsShareRound1:                 return "Round 2 →"
        case .lmsWinner, .predictorShare:     return "Finish"
        default:                              return "Next"
        }
    }

    var skipButtonTitle: String {
        switch self {
        case .lmsOpenRound1, .lmsOpenRound2, .predictorOpenRound:   return "Open for me"
        case .lmsEnterPicks1, .lmsEnterPicks2, .predictorEnterPredictions: return "Fill for me"
        case .lmsEnterResults1, .lmsEnterResults2, .predictorCloseRound:   return "Close for me"
        default:                                                      return "Skip"
        }
    }
}
