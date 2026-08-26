import SwiftUI
import SwiftData

/// Card restyle of `GameWizardView` — same state machine and phase logic
/// (`lmsPhase`/`predictorPhase`/`killerPhase`, live-state reads, ad-gated
/// share steps, re-enterable via `explicitGame`), copied rather than
/// shared, matching the rest of this branch. Differences from V1:
/// - Every destination that has a V2 screen now opens that V2 screen
///   instead (Players, New Game, Add Players, Open Round, Picks, Results,
///   Tie Resolution, Predictions, Predictor Results, Killer Open
///   Round/Predictions/Results). Share cards
///   (`SummaryShareView`/`PredictorShareView`/`KillerShareView`) have no V2
///   version yet and stay V1, matching `GameDetailViewV2` and friends.
/// - Killer's Scratchpad step is dropped entirely (not just left on V1) —
///   it was a v1 proof-of-concept intentionally dropped from V2, see
///   `KillerGameDetailViewV2`'s doc comment.
/// - Reworked around V2's refresh policy (`PushCoordinator`/
///   `SubmissionBadgeStore`/`FootballDataStore`), replacing V1's standalone
///   "Check Submission Queue" step: once a round is open and picks/
///   predictions are being collected, the wizard prompts to push to the PWA
///   (`PushCoordinator.push`, this game only) and offers an ad-gated
///   "Check Submissions" action (`SubmissionInboxViewV2`, filtered to this
///   game — same screen, now behind the same rewarded-ad gate every other
///   wizard utility step uses, not a free side door). Once results are due,
///   it offers the football-data update (`FootballDataStore.refresh`,
///   already self-ad-gates internally) before pulling scores.
/// - New front door when opened game-less from the Games portal's WIZARD
///   tile (`introCard`/`entryChoiceCard`/`continueGameCard`, all in the
///   `private extension` below): a one-time explainer, then New Game vs.
///   Continue an Existing Game — the latter a radio-button pick that sets
///   `resumedGame` and drops into that game's phase exactly like
///   `explicitGame` always has. This replaced the old per-row "resume
///   wizard" button on `GameSummaryRow` as the way to jump into a specific
///   game's wizard.
struct GameWizardViewV2: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(Entitlements.self) private var entitlements
    @Environment(PushCoordinator.self) private var pushCoordinator
    @Environment(EnabledLeagues.self) private var enabledLeagues
    @AppStorage("hasCompletedFirstRun") private var hasCompletedFirstRun = false
    @AppStorage("pwaSubmissionsEnabled") private var pwaSubmissionsEnabled = false
    /// The "Don't show this again" checkbox on `introCard` writes here —
    /// separate from `hasCompletedFirstRun` (the app-wide onboarding flag),
    /// since this is specifically about the Wizard's own front door and a
    /// manager should be able to suppress just this without it meaning
    /// anything about first-run onboarding generally.
    @AppStorage("wizardIntroDismissed") private var wizardIntroDismissed = false
    @Query(sort: \Game.createdAt, order: .reverse) private var games: [Game]
    @Query private var roster: [RosterMember]
    @State private var footballStore = FootballDataStore()

    /// The game this wizard is driving. `nil` = opened from the Games
    /// portal's WIZARD tile — the front door (`introCard`/`entryChoiceCard`/
    /// `continueGameCard`) decides whether that becomes a brand new game or
    /// an existing one (`resumedGame`) before the phase machine below ever
    /// sees a non-nil `game`.
    private let explicitGame: Game?

    @State private var showIntro: Bool
    @State private var dontShowIntroAgain = false
    @State private var entryChoice: WizardEntryChoice?
    @State private var selectedContinueGameID: UUID?
    /// Set once "Continue an Existing Game" → a selection → Next resolves —
    /// from here on `game` reads this exactly like `explicitGame`, so the
    /// rest of the file (phase machine, sheets, push/share prompts) can't
    /// tell the difference between this and having been opened directly on
    /// a specific game.
    @State private var resumedGame: Game?

    @State private var activeSheet: WizardSheetV2?
    /// Closing a round with everyone eliminated sets this (ResultsEntryViewV2
    /// needs the binding). We don't re-present off it — the phase machine
    /// surfaces the `resolveTie` card on its own — so we never re-present on
    /// the same sheet binding (which blanks the screen, see GameDetailViewV2).
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

    init(game: Game? = nil) {
        self.explicitGame = game
        // Read the flag directly (not via `@AppStorage`, which isn't wired
        // up yet at this point in init) — only ever relevant when opened
        // game-less; a per-game entry always skips the front door entirely.
        _showIntro = State(initialValue: game == nil && !UserDefaults.standard.bool(forKey: "wizardIntroDismissed"))
    }

    // MARK: Live state

    /// In new-game mode (`explicitGame == nil`) the wizard is game-less until *it*
    /// creates one — it never falls back to an existing game. The created game is
    /// resolved live (not captured in `onDismiss`, which can run before the
    /// `@Query` refreshes) as the newest game absent from the pre-create snapshot.
    private var game: Game? {
        if let explicitGame { return explicitGame }
        if let resumedGame { return resumedGame }
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

    private var phase: WizardPhaseV2 {
        guard let game else { return didVisitPlayers ? .createGame : .setupPlayers }
        switch game.mode {
        case .lms:       return lmsPhase(for: game)
        case .predictor: return predictorPhase(for: game)
        case .killer:    return killerPhase(for: game)
        }
    }

    private func lmsPhase(for game: Game) -> WizardPhaseV2 {
        if game.status == .complete { return .complete }
        if unresolvedTie { return .resolveTie }
        if openRound != nil { return picksComplete ? .enterResults : .enterPicks }
        if game.activePlayers.count < 2 && latestClosedRound == nil { return .addPlayers }
        return .openRound
    }

    private func predictorPhase(for game: Game) -> WizardPhaseV2 {
        if let round = openRound {
            return (round.status == .results || round.deadline < Date())
                ? .enterPredictorResults : .enterPredictions
        }
        if game.players.count < 2 && latestClosedRound == nil { return .addPlayers }
        return .openMatchday
    }

    /// Simpler than `lmsPhase` — Killer's close-round always auto-resolves
    /// (accuracy → hits → auto-split), so there's no unresolved-tie state to
    /// surface here, unlike LMS.
    private func killerPhase(for game: Game) -> WizardPhaseV2 {
        if game.status == .complete { return .complete }
        if let round = openRound {
            return KillerScoringService.allActivePlayersComplete(round: round, game: game)
                ? .enterKillerResults : .enterKillerPredictions
        }
        if game.activePlayers.count < 2 && latestClosedRound == nil { return .addPlayers }
        return .openKillerRound
    }

    var body: some View {
        NavigationStack {
            switch game?.mode {
            case .lms: scenedBody.v2LMSFormScene()
            case .predictor: scenedBody.v2PredictorFormScene()
            case .killer: scenedBody.v2KillerFormScene()
            case nil: scenedBody.v2TrophyRoomScene()
            }
        }
    }

    private var scenedBody: some View {
        ScrollView {
            LazyVStack(spacing: V2Theme.Spacing.section) {
                if showIntro {
                    introCard
                } else if explicitGame == nil && entryChoice == nil {
                    entryChoiceCard
                } else if entryChoice == .continueGame && resumedGame == nil {
                    continueGameCard
                } else {
                    heroCard
                    actionsCard
                }
            }
            .padding(.horizontal, V2Theme.Spacing.horizontal)
            .padding(.vertical, V2Theme.Spacing.section)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .v2FloatingHeader("Guided Setup", showBack: false) {
            Button("Cancel") { dismiss() }
                .foregroundStyle(V2Theme.textSecondary)
        }
        .sheet(item: $activeSheet, onDismiss: afterSheet) { which in
            sheetContent(which)
        }
        // Follow-up round after a reinstating resolution — presented at the top
        // level (never stacked on the resolution sheet).
        .sheet(item: $autoOpenType) { type in
            if let game {
                OpenRoundViewV2(game: game, roundType: type, tint: V2Theme.Mode.color(for: game.mode))
            }
        }
    }

    private var heroCard: some View {
        let card = card(for: phase)
        return Card(floating: true) {
            VStack(spacing: 14) {
                Image(systemName: card.icon)
                    .font(.system(size: 44))
                    .foregroundStyle(V2Theme.accent)
                if let context = contextLabel {
                    Text(context)
                        .font(V2Theme.Typography.metadata)
                        .foregroundStyle(V2Theme.textSecondary)
                }
                Text(card.title)
                    .font(V2Theme.Typography.pageTitle)
                    .foregroundStyle(V2Theme.textPrimary)
                    .multilineTextAlignment(.center)
                Text(card.detail)
                    .font(.subheadline)
                    .foregroundStyle(V2Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if let hint = card.hint {
                    Label(hint, systemImage: "hand.wave")
                        .font(.caption)
                        .foregroundStyle(V2Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var actionsCard: some View {
        let card = card(for: phase)
        Card(floating: true) {
            VStack(spacing: 10) {
                if let primary = card.primary {
                    PrimaryButton(title: primary.label) { open(primary.sheet) }
                }
                // The roster step is optional ("in case you want to add anyone") —
                // a Continue moves on to creating the game.
                if phase == .setupPlayers {
                    Button("Continue") { didVisitPlayers = true }
                        .font(.body.weight(.semibold))
                        .foregroundStyle(V2Theme.textSecondary)
                }
                if card.promptPush { pushRow }
                ForEach(card.secondaryActions, id: \.sheet) { action in
                    ActionRow(title: action.label, icon: "bell.badge") { open(action.sheet) }
                }
                if card.promptFootballUpdate { footballUpdateRow }
                ForEach(card.shares, id: \.sheet) { share in
                    ActionRow(title: share.label, icon: "square.and.arrow.up") { open(share.sheet) }
                }
                if card.showFinish {
                    PrimaryButton(title: "Finish") { finish() }
                }
            }
        }
    }

    /// Pushes this one game's open round to the PWA — same
    /// `PushCoordinator.push` call `GamesPortalViewV2`'s PUSH tile makes,
    /// just scoped to `game.id` instead of routing through
    /// `PushGamePickerViewV2`'s picker, since the wizard already knows
    /// exactly which game it's driving. Not ad-gated — Push never has been
    /// anywhere else in V2 either.
    @ViewBuilder
    private var pushRow: some View {
        if entitlements.canUseCloud && pwaSubmissionsEnabled {
            ActionRow(
                title: pushCoordinator.isPushing ? "Pushing to Players…" : "Push to Players",
                icon: "arrow.triangle.2.circlepath",
                isEnabled: !pushCoordinator.isPushing
            ) {
                guard let game else { return }
                Task { await pushCoordinator.push(context: context, gameIDs: [game.id]) }
            }
        }
    }

    /// Pulls fresh fixtures/standings before results are entered —
    /// `FootballDataStore.refresh` is already ad-gated internally (skipped
    /// for subscribers via `AdGate`), so this doesn't need its own gate.
    private var footballUpdateRow: some View {
        Button {
            footballStore.refresh(leagues: enabledLeagues.leagues)
        } label: {
            HStack {
                Label {
                    Text(footballStore.isLoading ? "Updating football data…" : "Update football data")
                } icon: {
                    if footballStore.isLoading {
                        V2LoadingIndicator(size: 20)
                    } else {
                        Image(systemName: "sportscourt")
                    }
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption)
            }
        }
        .foregroundStyle(V2Theme.accent)
        .opacity(!footballStore.isLoading && !footballStore.isThrottled ? 1 : 0.4)
        .disabled(footballStore.isLoading || footballStore.isThrottled)
    }

    // MARK: Cards

    private struct Action { let label: String; let sheet: WizardSheetV2 }
    private struct PhaseCard {
        let icon: String
        let title: String
        let detail: String
        var hint: String?
        var primary: Action?
        var shares: [Action] = []
        var secondaryActions: [Action] = []  // ad-gated utility buttons (e.g. Check Submissions)
        var promptPush: Bool = false
        var promptFootballUpdate: Bool = false
        var showFinish: Bool = false
    }

    /// Shared across LMS/Predictor/Killer pick-collection phases — only
    /// offered once cloud submissions are actually reachable for this game.
    private var checkSubmissionsAction: [Action] {
        guard entitlements.canUseCloud, pwaSubmissionsEnabled, game?.cloudGameToken != nil else { return [] }
        return [.init(label: "Check Submissions", sheet: .checkSubmissions)]
    }

    private func card(for phase: WizardPhaseV2) -> PhaseCard {
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
                hint: "Still waiting on players? You don't have to do this now — close the wizard and come back any time by tapping the wand icon "
                    + "on this game. It picks up right here.",
                primary: .init(label: "Enter Picks", sheet: .picks),
                shares: [.init(label: "Share Fixtures Card", sheet: .shareFixtures)],
                secondaryActions: checkSubmissionsAction,
                promptPush: true)
        case .enterResults:
            return PhaseCard(
                icon: "flag.checkered",
                title: "Enter results & close",
                detail: "Pull the results (or set them), then close the round to work out who's out.",
                primary: .init(label: "Enter Results / Close", sheet: .results),
                shares: [.init(label: "Share Picks Card", sheet: .sharePicks)],
                promptFootballUpdate: true)
        case .resolveTie:
            return PhaseCard(
                icon: "exclamationmark.triangle",
                title: "Resolve the round",
                detail: "Everyone still in went out together — no clear winner. Choose how it ends: split the win, roll the week for the tied players, "
                    + "or bring everyone back in.",
                primary: .init(label: "Resolve Round", sheet: .resolveTie),
                shares: [.init(label: "Share Results Card", sheet: .shareResults)])
        case .complete:
            let shares: [Action]
            if game?.mode == .killer {
                shares = [
                    .init(label: "Share Weekly Results", sheet: .killerShareWeeklyResults),
                    .init(label: "Share Final Result", sheet: .killerShareWinner)
                ]
            } else {
                var lmsShares: [Action] = [.init(label: "Share Results Card", sheet: .shareResults)]
                if game?.lastOutcome != nil { lmsShares.append(.init(label: "Share Outcome Card", sheet: .shareOutcome)) }
                shares = lmsShares
            }
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
            return PhaseCard(
                icon: "checklist",
                title: "Collect predictions",
                detail: "Players submit their predicted scores via the public link. You can also enter predictions on their behalf.",
                hint: "Not everyone in yet? Close the wizard and come back any time — tap the wand icon on this game to resume here.",
                primary: .init(label: "Enter Predictions", sheet: .predictorPredictions),
                shares: [.init(label: "Share Fixtures Card", sheet: .shareFixtures)],
                secondaryActions: checkSubmissionsAction,
                promptPush: true)
        case .enterPredictorResults:
            return PhaseCard(
                icon: "flag.checkered",
                title: "Enter scores & close",
                detail: "Add the final scores for each fixture, then close the matchday to award points.",
                primary: .init(label: "Enter Results / Close", sheet: .predictorResults),
                shares: [.init(label: "Share Entry Closed Card", sheet: .shareEntryClosed)],
                promptFootballUpdate: true)

        // MARK: Killer phases

        case .openKillerRound:
            let shares: [Action] = latestClosedRound != nil ? [
                .init(label: "Share Weekly Results", sheet: .killerShareWeeklyResults),
                .init(label: "Share Accuracy Table", sheet: .killerShareStandings)
            ] : []
            return PhaseCard(
                icon: "calendar.badge.plus",
                title: "Open the next round",
                detail: "Pick the Manager Picked Games this round runs on and set the predictions deadline.",
                primary: .init(label: "Open Round", sheet: .killerOpenRound),
                shares: shares)
        case .enterKillerPredictions:
            let isKillPhase = game.flatMap { g in openRound.map { KillerScoringService.phase(for: $0, game: g) } } == .kill
            return PhaseCard(
                icon: "checklist",
                title: "Collect predictions",
                detail: isKillPhase
                    ? "Enter each player's Home/Draw/Away guess for every fixture, plus who they're targeting with each Hit."
                    : "Enter each player's Home/Draw/Away guess for every fixture — correct guesses earn extra lives this early.",
                hint: "Not everyone in yet? Close the wizard and come back any time — tap the wand icon on this game to resume here.",
                primary: .init(label: "Enter Predictions", sheet: .killerPredictions),
                shares: [.init(label: "Share Fixtures Card", sheet: .killerShareFixtures)],
                secondaryActions: checkSubmissionsAction,
                promptPush: true)
        case .enterKillerResults:
            let isKillPhase = game.flatMap { g in openRound.map { KillerScoringService.phase(for: $0, game: g) } } == .kill
            return PhaseCard(
                icon: "flag.checkered",
                title: "Enter results & close",
                detail: "Pull the results (or set them), then close the round to work out who's out.",
                primary: .init(label: "Enter Results / Close", sheet: .killerResults),
                shares: isKillPhase ? [.init(label: "Share Player Key Card", sheet: .killerSharePlayerKey)] : [],
                promptFootballUpdate: true)
        }
    }

    // MARK: Sheets

    @ViewBuilder
    private func sheetContent(_ which: WizardSheetV2) -> some View {
        switch which {
        case .players:  PlayersViewV2()
        case .newGame:  NewGameViewV2()
        case .addPlayers:
            if let game { AddPlayersViewV2(game: game) }
        case .openRound:
            if let game { OpenRoundViewV2(game: game, tint: V2Theme.Mode.color(for: game.mode)) }
        case .checkSubmissions:
            if let gameToken = game?.cloudGameToken {
                NavigationStack { SubmissionInboxViewV2(filterGameToken: gameToken) }
            }
        case .picks, .results, .resolveTie,
             .shareFixtures, .sharePicks, .shareResults, .shareOutcome:
            lmsSheetContent(which)
        case .predictorPredictions, .predictorResults,
             .shareEntryClosed, .shareWeeklyResults, .shareLeagueTable:
            predictorSheetContent(which)
        case .killerOpenRound:
            if let game { KillerOpenRoundViewV2(game: game) }
        case .killerPredictions, .killerResults,
             .killerShareFixtures, .killerSharePlayerKey, .killerShareWeeklyResults,
             .killerShareStandings, .killerShareWinner:
            killerSheetContent(which)
        }
    }

    @ViewBuilder
    private func lmsSheetContent(_ which: WizardSheetV2) -> some View {
        switch which {
        case .picks:
            if let game, let round = openRound { PicksEntryViewV2(game: game, round: round) }
        case .results:
            if let game, let round = openRound {
                ResultsEntryViewV2(game: game, round: round, pendingResolve: $pendingResolve)
            }
        case .resolveTie:
            if let game {
                TieResolutionViewV2(game: game, tiedPlayers: lastRoundTied) { followUp in
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
    private func predictorSheetContent(_ which: WizardSheetV2) -> some View {
        switch which {
        case .predictorPredictions:
            if let game, let round = openRound { PredictionsEntryViewV2(game: game, round: round) }
        case .predictorResults:
            if let game, let round = openRound { PredictorResultsEntryViewV2(game: game, round: round) }
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

    /// Killer share cards route through `KillerShareView`/`KillerCardData`,
    /// never `SummaryShareView` — that reads `round.picks`/`round.predictions`,
    /// which are always empty for a Killer round and would render a blank card.
    @ViewBuilder
    private func killerSheetContent(_ which: WizardSheetV2) -> some View {
        switch which {
        case .killerPredictions:
            if let game, let round = openRound { KillerPredictionsEntryViewV2(game: game, round: round) }
        case .killerResults:
            if let game, let round = openRound { KillerResultsEntryViewV2(game: game, round: round) }
        case .killerShareFixtures:
            if let game, let round = openRound { KillerShareView(game: game, round: round, type: .fixtures) }
        case .killerSharePlayerKey:
            if let game, let round = openRound { KillerShareView(game: game, round: round, type: .playerKey) }
        case .killerShareWeeklyResults:
            if let game, let round = latestClosedRound { KillerShareView(game: game, round: round, type: .weeklyResults) }
        case .killerShareStandings:
            if let game, let round = latestClosedRound ?? openRound {
                KillerShareView(game: game, round: round, type: .standings)
            }
        case .killerShareWinner:
            if let game, let round = latestClosedRound { KillerShareView(game: game, round: round, type: .winner) }
        default: EmptyView()
        }
    }

    /// Opens a step's screen. Share-card steps cost a rewarded ad for free users —
    /// the same gate the real screens use (GameDetailViewV2 / PicksEntryViewV2) —
    /// so the wizard isn't an ad-free side door to the shareable cards.
    private func open(_ which: WizardSheetV2) {
        // Opening New Game starts adoption: snapshot the existing games so the one
        // created in the sheet is recognised live once the @Query refreshes.
        if which == .newGame {
            gameIDsBeforeCreate = Set(games.map(\.id))
            didStartCreate = true
        }
        if which.isAdGated {
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

private enum WizardEntryChoice {
    case new, continueGame
}

/// Front door — split into its own extension purely to keep the main
/// struct's body under SwiftLint's `type_body_length`, not for any
/// access-boundary reason (still reaches the struct's own `@State`
/// directly).
private extension GameWizardViewV2 {
    /// A short "Round N" / status line above the card, so a resumed wizard makes
    /// clear where in the game it picked up.
    var contextLabel: String? {
        guard let game else { return nil }
        let prefix = game.mode == .predictor ? "Matchday" : "Round"
        if let round = openRound { return "\(prefix) \(round.roundNumber)" }
        if let last = latestClosedRound, game.status != .complete { return "\(prefix) \(last.roundNumber)" }
        return nil
    }

    /// Shown once ever (per `wizardIntroDismissed`, unless the checkbox is
    /// left unchecked) before the very first game-less open — never shown
    /// when opened directly on a game, since there's nothing to explain
    /// there that the phase cards below don't already say in context.
    var introCard: some View {
        Card(floating: true) {
            VStack(spacing: 14) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 44))
                    .foregroundStyle(V2Theme.accent)
                Text("The Wizard")
                    .font(V2Theme.Typography.pageTitle)
                    .foregroundStyle(V2Theme.textPrimary)
                Text("One step at a time: start a new game, or pick up an existing one right where you left off. Each screen tells you where you are and what's next, and does it for you.")
                    .font(.subheadline)
                    .foregroundStyle(V2Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    dontShowIntroAgain.toggle()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: dontShowIntroAgain ? "checkmark.square.fill" : "square")
                            .foregroundStyle(dontShowIntroAgain ? V2Theme.accent : V2Theme.textTertiary)
                        Text("Don't show this again")
                            .font(.footnote)
                            .foregroundStyle(V2Theme.textSecondary)
                    }
                }
                .buttonStyle(.plain)
                PrimaryButton(title: "Continue") {
                    if dontShowIntroAgain { wizardIntroDismissed = true }
                    showIntro = false
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// The only fork in the front door — everything past this point (New
    /// Game's setup prefix, or an existing game's own phase) is the same
    /// flow the wizard always had.
    var entryChoiceCard: some View {
        Card(floating: true) {
            VStack(spacing: 14) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 44))
                    .foregroundStyle(V2Theme.accent)
                Text("New game, or continue one?")
                    .font(V2Theme.Typography.pageTitle)
                    .foregroundStyle(V2Theme.textPrimary)
                    .multilineTextAlignment(.center)
                PrimaryButton(title: "New Game") { entryChoice = .new }
                if !games.isEmpty {
                    Button("Continue an Existing Game") { entryChoice = .continueGame }
                        .font(.body.weight(.semibold))
                        .foregroundStyle(V2Theme.textSecondary)
                        .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// Radio-button game list — picking one and tapping Next sets
    /// `resumedGame`, after which this screen behaves exactly like being
    /// opened directly on that game (see `game`'s doc comment).
    var continueGameCard: some View {
        Card(floating: true) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Continue which game?")
                    .font(V2Theme.Typography.pageTitle)
                    .foregroundStyle(V2Theme.textPrimary)
                VStack(spacing: 4) {
                    ForEach(games) { candidate in
                        Button {
                            selectedContinueGameID = candidate.id
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: selectedContinueGameID == candidate.id ? "largecircle.fill.circle" : "circle")
                                    .foregroundStyle(selectedContinueGameID == candidate.id ? V2Theme.accent : V2Theme.textTertiary)
                                Image(systemName: V2Theme.Mode.icon(for: candidate.mode))
                                    .foregroundStyle(V2Theme.Mode.color(for: candidate.mode))
                                    .frame(width: 20)
                                Text(candidate.name)
                                    .foregroundStyle(V2Theme.textPrimary)
                                    .lineLimit(1)
                                Spacer()
                            }
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                PrimaryButton(title: "Next", isEnabled: selectedContinueGameID != nil) {
                    resumedGame = games.first { $0.id == selectedContinueGameID }
                }
                Button("Back") {
                    entryChoice = nil
                    selectedContinueGameID = nil
                }
                .font(.body.weight(.semibold))
                .foregroundStyle(V2Theme.textSecondary)
            }
        }
    }
}

private enum WizardPhaseV2 {
    // Shared setup prefix
    case setupPlayers, createGame, addPlayers
    // LMS phases
    case openRound, enterPicks, enterResults, resolveTie, complete
    // Predictor phases
    case openMatchday, enterPredictions, enterPredictorResults
    // Killer phases
    case openKillerRound, enterKillerPredictions, enterKillerResults
}

private enum WizardSheetV2: String, Identifiable {
    // Shared
    case players, newGame, addPlayers, openRound, checkSubmissions
    // LMS
    case picks, results, resolveTie
    case shareFixtures, sharePicks, shareResults, shareOutcome
    // Predictor
    case predictorPredictions, predictorResults
    case shareEntryClosed, shareWeeklyResults, shareLeagueTable
    // Killer
    case killerOpenRound, killerPredictions, killerResults
    case killerShareFixtures, killerSharePlayerKey, killerShareWeeklyResults
    case killerShareStandings, killerShareWinner
    var id: String { rawValue }

    /// Costs a rewarded ad for free users — the same gate the real screens
    /// use (GameDetailViewV2 / PicksEntryViewV2) for share cards, now also
    /// covering `checkSubmissions` so it isn't a free side door either.
    var isAdGated: Bool {
        switch self {
        case .shareFixtures, .sharePicks, .shareResults, .shareOutcome,
             .shareEntryClosed, .shareWeeklyResults, .shareLeagueTable,
             .killerShareFixtures, .killerSharePlayerKey, .killerShareWeeklyResults,
             .killerShareStandings, .killerShareWinner, .checkSubmissions: return true
        default: return false
        }
    }
}
