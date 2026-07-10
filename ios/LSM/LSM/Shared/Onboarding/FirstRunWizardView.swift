import SwiftUI
import SwiftData

/// A guided walkthrough that *drives the real screens* (Players, New Game, Add
/// Players, Open Round, Picks, Results, tie resolution, share cards) in order —
/// no duplicate logic — and reads live state to decide what to show next.
///
/// It is **state-driven and re-enterable**: launched with no game it runs the
/// first-run setup; launched for a specific game (swipe a game right) it resumes
/// at that game's current phase and loops through every round — enter picks →
/// share → results/close → resolve a tie → open the next round → … — until the
/// game completes. The normal flow (GameDetailView buttons) is untouched; this is
/// purely an optional on-ramp/companion the manager can pick up and put down.
struct GameWizardView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Entitlements.self) private var entitlements
    @AppStorage("hasCompletedFirstRun") private var hasCompletedFirstRun = false
    @AppStorage("pwaSubmissionsEnabled") private var pwaSubmissionsEnabled = false
    @Query(sort: \Game.createdAt, order: .reverse) private var games: [Game]
    @Query private var roster: [RosterMember]

    /// The game this wizard is driving. `nil` = first-run: there is no game yet,
    /// so it falls back to the newest game once one is created mid-flow.
    private let explicitGame: Game?

    @State private var activeSheet: WizardSheet?
    /// Closing a round with everyone eliminated sets this (ResultsEntryView needs
    /// the binding). We don't re-present off it — the phase machine surfaces the
    /// `resolveTie` card on its own — so we never re-present on the same sheet
    /// binding (which blanks the screen, see GameDetailView).
    @State private var pendingResolve = false
    /// A resolution that reinstates players opens a follow-up round next.
    @State private var pendingAutoOpen: RoundType?
    @State private var autoOpenType: RoundType?
    /// New-game mode (no `explicitGame`): the setup prefix is an ordered walkthrough
    /// — roster (optional) → create game → assign players → … — before the round
    /// loop takes over. These flags drive that prefix so we never resume a
    /// pre-existing game from the "New Game" entry point.
    @State private var didVisitPlayers = false   // passed the (optional) roster step
    @State private var didStartCreate = false     // opened New Game (so a created game is adopted)
    /// Game ids that existed just before opening New Game — so the freshly created
    /// game is the one not in this set (read live, after the @Query refreshes).
    @State private var gameIDsBeforeCreate: Set<UUID> = []

    init(game: Game? = nil) { self.explicitGame = game }

    // MARK: Live state

    /// In new-game mode (`explicitGame == nil`) the wizard is game-less until *it*
    /// creates one — it never falls back to an existing game. The created game is
    /// resolved live (not captured in `onDismiss`, which can run before the
    /// `@Query` refreshes) as the newest game absent from the pre-create snapshot.
    private var game: Game? {
        if let explicitGame { return explicitGame }
        guard didStartCreate else { return nil }
        return games.first { !gameIDsBeforeCreate.contains($0.id) }
    }
    private var openRound: Round? {
        guard let r = game?.currentRound, r.status != .closed else { return nil }
        return r
    }
    private var latestClosedRound: Round? {
        game?.rounds.filter { $0.status == .closed }.max(by: { $0.roundNumber < $1.roundNumber })
    }
    private var picksComplete: Bool {
        guard let game, let round = openRound, !round.picks.isEmpty else { return false }
        return !game.activePlayers.contains { p in !round.picks.contains { $0.player?.id == p.id } }
    }
    private var unresolvedTie: Bool {
        guard let game else { return false }
        return game.status == .active && openRound == nil
            && game.activePlayers.isEmpty && latestClosedRound != nil
    }
    private var lastRoundTied: [Player] {
        guard let game, let round = latestClosedRound else { return [] }
        return game.players.filter { player in round.picks.contains { $0.player?.id == player.id } }
    }

    // MARK: Phase machine

    private var phase: WizardPhase {
        guard let game else { return didVisitPlayers ? .createGame : .setupPlayers }
        switch game.mode {
        case .lms:       return lmsPhase(for: game)
        case .predictor: return predictorPhase(for: game)
        // The tutorial only ever creates LMS/Predictor demo games — Killer has
        // no guided wizard yet (see predictor-wizard-demo-todo memory).
        case .killer:    return .complete
        }
    }

    private func lmsPhase(for game: Game) -> WizardPhase {
        if game.status == .complete { return .complete }
        if unresolvedTie { return .resolveTie }
        if openRound != nil { return picksComplete ? .enterResults : .enterPicks }
        if game.activePlayers.count < 2 && latestClosedRound == nil { return .addPlayers }
        return .openRound
    }

    private func predictorPhase(for game: Game) -> WizardPhase {
        if let round = openRound {
            return (round.status == .results || round.deadline < Date())
                ? .enterPredictorResults : .enterPredictions
        }
        if game.players.count < 2 && latestClosedRound == nil { return .addPlayers }
        return .openMatchday
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                let card = card(for: phase)
                VStack(spacing: 16) {
                    Image(systemName: card.icon)
                        .font(.system(size: 52))
                        .foregroundStyle(.tint)
                    if let context = contextLabel {
                        Text(context)
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Text(card.title)
                        .font(.title2.bold()).multilineTextAlignment(.center)
                    Text(card.detail)
                        .font(.body).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    if let hint = card.hint {
                        Label(hint, systemImage: "hand.wave")
                            .font(.footnote).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 28)
                Spacer()

                if let primary = card.primary {
                    Button { open(primary.sheet) } label: {
                        Text(primary.label).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                // The roster step is optional ("in case you want to add anyone") —
                // a Continue moves on to creating the game.
                if phase == .setupPlayers {
                    Button("Continue") { didVisitPlayers = true }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                }
                ForEach(card.secondaryActions, id: \.sheet) { action in
                    Button { open(action.sheet) } label: {
                        Text(action.label).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                ForEach(card.shares, id: \.sheet) { share in
                    Button { open(share.sheet) } label: {
                        Label(share.label, systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                if card.showFinish {
                    Button("Finish") { finish() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                }
            }
            .padding()
            .navigationTitle("Guided Setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Exit") { dismiss() } }
            }
            .sheet(item: $activeSheet, onDismiss: afterSheet) { which in
                sheetContent(which)
            }
            // Follow-up round after a reinstating resolution — presented at the top
            // level (never stacked on the resolution sheet).
            .sheet(item: $autoOpenType) { type in
                OpenRoundView(game: game!, roundType: type)
            }
        }
    }

    /// A short "Round N" / status line above the card, so a resumed wizard makes
    /// clear where in the game it picked up.
    private var contextLabel: LocalizedStringKey? {
        guard let game else { return nil }
        let prefix = game.mode == .predictor ? "Matchday" : "Round"
        if let round = openRound { return "\(prefix) \(round.roundNumber)" }
        if let last = latestClosedRound, game.status != .complete { return "\(prefix) \(last.roundNumber)" }
        return nil
    }

    // MARK: Cards

    private struct Action { let label: LocalizedStringKey; let sheet: WizardSheet }
    private struct PhaseCard {
        let icon: String
        let title: LocalizedStringKey
        let detail: LocalizedStringKey
        var hint: LocalizedStringKey?
        var primary: Action?
        var shares: [Action] = []
        var secondaryActions: [Action] = []  // non-ad-gated utility buttons
        var showFinish: Bool = false
    }

    private func card(for phase: WizardPhase) -> PhaseCard {
        switch phase {
        case .setupPlayers:
            return PhaseCard(
                icon: "person.2.fill",
                title: "Set up your players",
                detail: "Add the people who'll play, and optionally group them (e.g. \"Office\"). This is your reusable roster.",
                primary: .init(label: "Open Players", sheet: .players))
        case .createGame:
            return PhaseCard(
                icon: "trophy.fill",
                title: "Create the game",
                detail: "Name it, choose whether you're playing, and set anonymity for shared cards.",
                primary: .init(label: "New Game", sheet: .newGame))
        case .addPlayers:
            return PhaseCard(
                icon: "person.badge.plus",
                title: "Assign players to the game",
                detail: "Pull people from your roster into this game — you need at least two to play.",
                primary: .init(label: "Assign Players", sheet: .addPlayers))
        case .openRound:
            return PhaseCard(
                icon: "calendar.badge.plus",
                title: "Open the next round",
                detail: "Pick the fixtures this round runs on and set the picks deadline.",
                primary: .init(label: "Open Round", sheet: .openRound),
                shares: latestClosedRound != nil ? [.init(label: "Share Results Card", sheet: .shareResults)] : [])
        case .enterPicks:
            return PhaseCard(
                icon: "checklist",
                title: "Enter & assign picks",
                detail: "Record each player's team, then Auto-Assign anyone who didn't reply in time.",
                hint: LocalizedStringKey(
                    "Still waiting on players? You don't have to do this now — close the wizard and come back any time by swiping the game to the right. "
                        + "It picks up right here."),
                primary: .init(label: "Enter Picks", sheet: .picks),
                shares: [.init(label: "Share Fixtures Card", sheet: .shareFixtures)])
        case .enterResults:
            return PhaseCard(
                icon: "flag.checkered",
                title: "Enter results & close",
                detail: "Pull the results (or set them), then close the round to work out who's out.",
                primary: .init(label: "Enter Results / Close", sheet: .results),
                shares: [.init(label: "Share Picks Card", sheet: .sharePicks)])
        case .resolveTie:
            return PhaseCard(
                icon: "exclamationmark.triangle",
                title: "Resolve the round",
                detail: LocalizedStringKey(
                    "Everyone still in went out together — no clear winner. Choose how it ends: split the win, roll the week for the tied players, "
                        + "or bring everyone back in."),
                primary: .init(label: "Resolve Round", sheet: .resolveTie),
                shares: [.init(label: "Share Results Card", sheet: .shareResults)])
        case .complete:
            var shares: [Action] = [.init(label: "Share Results Card", sheet: .shareResults)]
            if game?.lastOutcome != nil { shares.append(.init(label: "Share Outcome Card", sheet: .shareOutcome)) }
            return PhaseCard(
                icon: "party.popper.fill",
                title: "That's a wrap!",
                detail: "The game's done. Share the final result, and you're all set — start a new game whenever you like.",
                shares: shares,
                showFinish: true)

        // MARK: Predictor phases

        case .openMatchday:
            let shares: [Action] = latestClosedRound != nil ? [
                .init(label: "Share Weekly Results", sheet: .shareWeeklyResults),
                .init(label: "Share League Table", sheet: .shareLeagueTable)
            ] : []
            return PhaseCard(
                icon: "calendar.badge.plus",
                title: "Open the next matchday",
                detail: "Select fixtures for the matchday and set the predictions deadline.",
                primary: .init(label: "Open Matchday", sheet: .openRound),
                shares: shares)
        case .enterPredictions:
            let canSeeQueue = entitlements.canUseCloud && pwaSubmissionsEnabled
                && game?.cloudGameToken != nil
            var predictionsActions: [Action] = []
            if canSeeQueue { predictionsActions.append(.init(label: "Check Submission Queue", sheet: .submissionQueue)) }
            return PhaseCard(
                icon: "checklist",
                title: "Collect predictions",
                detail: "Players submit their predicted scores via the public link. You can also enter predictions on their behalf.",
                hint: "Not everyone in yet? Close the wizard and come back any time — swipe the game right to resume here.",
                primary: .init(label: "Enter Predictions", sheet: .predictorPredictions),
                shares: [.init(label: "Share Fixtures Card", sheet: .shareFixtures)],
                secondaryActions: predictionsActions)
        case .enterPredictorResults:
            return PhaseCard(
                icon: "flag.checkered",
                title: "Enter scores & close",
                detail: "Add the final scores for each fixture, then close the matchday to award points.",
                primary: .init(label: "Enter Results / Close", sheet: .predictorResults),
                shares: [.init(label: "Share Entry Closed Card", sheet: .shareEntryClosed)])
        }
    }

    // MARK: Sheets

    @ViewBuilder
    private func sheetContent(_ which: WizardSheet) -> some View {
        switch which {
        case .players:  PlayersView()
        case .newGame:  NewGameView()
        case .addPlayers:
            if let game { AddPlayersView(game: game) }
        case .openRound:
            if let game { OpenRoundView(game: game) }
        case .picks, .results, .resolveTie,
             .shareFixtures, .sharePicks, .shareResults, .shareOutcome:
            lmsSheetContent(which)
        case .predictorPredictions, .predictorResults, .submissionQueue,
             .shareEntryClosed, .shareWeeklyResults, .shareLeagueTable:
            predictorSheetContent(which)
        }
    }

    @ViewBuilder
    private func lmsSheetContent(_ which: WizardSheet) -> some View {
        switch which {
        case .picks:
            if let game, let round = openRound { PicksEntryView(game: game, round: round) }
        case .results:
            if let game, let round = openRound {
                ResultsEntryView(game: game, round: round, pendingResolve: $pendingResolve)
            }
        case .resolveTie:
            if let game {
                TieResolutionView(game: game, tiedPlayers: lastRoundTied) { followUp in
                    pendingAutoOpen = followUp
                }
            }
        case .shareFixtures:
            if let game, let round = openRound {
                SummaryShareView(game: game, round: round, type: .fixtures)
            }
        case .sharePicks:
            if let game, let round = openRound {
                SummaryShareView(game: game, round: round, type: .picks)
            }
        case .shareResults:
            if let game, let round = latestClosedRound {
                SummaryShareView(game: game, round: round, type: .results)
            }
        case .shareOutcome:
            if let game, let ending = game.lastOutcome, let round = latestClosedRound {
                SummaryShareView(game: game, round: round, type: .outcome(ending))
            }
        default: EmptyView()
        }
    }

    @ViewBuilder
    private func predictorSheetContent(_ which: WizardSheet) -> some View {
        switch which {
        case .predictorPredictions:
            if let game, let round = openRound { PredictionsEntryView(game: game, round: round) }
        case .predictorResults:
            if let game, let round = openRound { PredictorResultsEntryView(game: game, round: round) }
        case .submissionQueue:
            if let game, let round = openRound, let gameToken = game.cloudGameToken {
                NavigationStack { SubmissionQueueView(game: game, round: round, gameToken: gameToken) }
            }
        case .shareEntryClosed:
            if let game, let round = openRound ?? latestClosedRound {
                PredictorShareView(game: game, round: round, type: .entryClosed)
            }
        case .shareWeeklyResults:
            if let game, let round = latestClosedRound {
                PredictorShareView(game: game, round: round, type: .weeklyResults)
            }
        case .shareLeagueTable:
            if let game, let round = latestClosedRound {
                PredictorShareView(game: game, round: round, type: .league)
            }
        default: EmptyView()
        }
    }

    /// Opens a step's screen. Share-card steps cost a rewarded ad for free users —
    /// the same gate the real screens use (GameDetailView / PicksEntryView) — so
    /// the wizard isn't an ad-free side door to the shareable cards.
    private func open(_ which: WizardSheet) {
        // Opening New Game starts adoption: snapshot the existing games so the one
        // created in the sheet is recognised live once the @Query refreshes.
        if which == .newGame {
            gameIDsBeforeCreate = Set(games.map(\.id))
            didStartCreate = true
        }
        if which.isShare {
            AdGate.run { activeSheet = which }
        } else {
            activeSheet = which
        }
    }

    /// After a sheet closes, open the follow-up round a reinstating resolution
    /// asked for — via the separate `autoOpenType` binding, so we never re-present
    /// on the same sheet binding mid-dismiss (which blanks the screen).
    private func afterSheet() {
        if let type = pendingAutoOpen {
            pendingAutoOpen = nil
            autoOpenType = type
        }
    }

    private func finish() {
        if explicitGame == nil { hasCompletedFirstRun = true }
        dismiss()
    }
}

private enum WizardPhase {
    // Shared setup prefix
    case setupPlayers, createGame, addPlayers
    // LMS phases
    case openRound, enterPicks, enterResults, resolveTie, complete
    // Predictor phases
    case openMatchday, enterPredictions, enterPredictorResults
}

enum WizardSheet: String, Identifiable {
    // Shared
    case players, newGame, addPlayers, openRound
    // LMS
    case picks, results, resolveTie
    case shareFixtures, sharePicks, shareResults, shareOutcome
    // Predictor
    case predictorPredictions, predictorResults, submissionQueue
    case shareEntryClosed, shareWeeklyResults, shareLeagueTable
    var id: String { rawValue }

    var isShare: Bool {
        switch self {
        case .shareFixtures, .sharePicks, .shareResults, .shareOutcome,
             .shareEntryClosed, .shareWeeklyResults, .shareLeagueTable: return true
        default: return false
        }
    }
}
