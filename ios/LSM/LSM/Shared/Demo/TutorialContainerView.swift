import SwiftUI
import SwiftData

/// Full-screen tutorial container. Presents the real `GameDetailView` or
/// `PredictorGameDetailView` for a demo game, overlaid with `TutorialDimOverlay`.
/// All tutorial data is seeded at start; any prior demo game is cleared first.
struct TutorialContainerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(Entitlements.self) private var entitlements

    @State private var selectedMode: GameMode?

    @Query(filter: #Predicate<Game> { $0.isDemoData }, sort: \Game.createdAt, order: .reverse)
    private var tutorialGames: [Game]

    private var game: Game? {
        guard let id = TutorialManager.shared.tutorialGameID else { return nil }
        return tutorialGames.first { $0.id == id }
    }

    // State triggers for auto-advancement observed via .onChange
    private var openRoundsCount: Int {
        game?.rounds.filter { $0.status == .open }.count ?? 0
    }
    private var closedRoundsCount: Int {
        game?.rounds.filter { $0.status == .closed }.count ?? 0
    }
    private var openRoundPicksCount: Int {
        game?.rounds.first { $0.status == .open }?.picks.count ?? 0
    }
    private var openRoundPredictionsCount: Int {
        game?.rounds.first { $0.status == .open }?.predictions.count ?? 0
    }

    var body: some View {
        ZStack {
            if let mode = selectedMode, let game {
                NavigationStack {
                    if mode == .lms {
                        GameDetailView(game: game)
                    } else {
                        PredictorGameDetailView(game: game)
                    }
                }
                .environment(entitlements)
                .coordinateSpace(name: "tutorialRoot")

                if TutorialManager.shared.isActive {
                    TutorialDimOverlay(
                        onNext: { handleNext() },
                        onSkip: { handleSkip() },
                        onExit: { exitTutorial() }
                    )
                }
            } else {
                modePicker
            }
        }
        .interactiveDismissDisabled()
        .onChange(of: openRoundsCount)              { _, _ in autoAdvance() }
        .onChange(of: closedRoundsCount)            { _, _ in autoAdvance() }
        .onChange(of: openRoundPicksCount)          { _, _ in autoAdvance() }
        .onChange(of: openRoundPredictionsCount)    { _, _ in autoAdvance() }
        .onChange(of: game?.status)                 { _, _ in autoAdvance() }
    }

    // MARK: - Mode picker

    private var modePicker: some View {
        NavigationStack {
            List {
                Section {
                    Text("Pick a mode to see a complete example game with sample data. No real data is affected.")
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }
                Section {
                    modeTile(icon: "trophy.fill", title: "Last Man Standing",
                             subtitle: "Two full rounds — one winner.", color: .green) {
                        startTutorial(mode: .lms)
                    }
                    modeTile(icon: "list.number", title: "Predictor",
                             subtitle: "One matchday — predict every score.", color: .blue) {
                        startTutorial(mode: .predictor)
                    }
                }
            }
            .navigationTitle("See How It Works")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func modeTile(
        icon: String, title: String, subtitle: String, color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline).foregroundStyle(.primary)
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Start

    private func startTutorial(mode: GameMode) {
        // Always clear any leftover demo data before starting fresh
        TutorialDataService.clearTutorialData(context: context)
        try? context.save()

        TutorialDataService.seedLeagueCaches()

        let game: Game = mode == .lms
            ? TutorialDataService.createLMSGame(context: context)
            : TutorialDataService.createPredictorGame(context: context)

        // Players are pre-added so the .lmsPlayers step can show them immediately
        TutorialDataService.addPlayers(to: game, context: context)
        try? context.save()

        TutorialManager.shared.begin(gameID: game.id, mode: mode)
        selectedMode = mode
    }

    // MARK: - Auto-advancement (state-predicate driven)

    private func autoAdvance() {
        guard let game else { return }
        let step = TutorialManager.shared.currentStep
        let open = game.rounds.first { $0.status == .open }
        let closedCount = game.rounds.filter { $0.status == .closed }.count

        switch step {
        // LMS Round 1
        case .lmsOpenRound1:
            if open != nil && closedCount == 0 {
                TutorialManager.shared.advance(to: .lmsEnterPicks1)
            }
        case .lmsEnterPicks1:
            if let r = open {
                let active = game.activePlayers.count
                if active > 0 && r.picks.count >= active {
                    TutorialManager.shared.advance(to: .lmsEnterResults1)
                }
            }
        case .lmsEnterResults1:
            if closedCount == 1 {
                TutorialManager.shared.advance(to: .lmsShareRound1)
            }

        // LMS Round 2
        case .lmsOpenRound2:
            if open != nil && closedCount == 1 {
                TutorialManager.shared.advance(to: .lmsEnterPicks2)
            }
        case .lmsEnterPicks2:
            if let r = open {
                let active = game.activePlayers.count
                if active > 0 && r.picks.count >= active {
                    TutorialManager.shared.advance(to: .lmsEnterResults2)
                }
            }
        case .lmsEnterResults2:
            if game.status == .complete {
                TutorialManager.shared.advance(to: .lmsWinner)
            }

        // Predictor
        case .predictorOpenRound:
            if open != nil {
                TutorialManager.shared.advance(to: .predictorEnterPredictions)
            }
        case .predictorEnterPredictions:
            if let r = open {
                let expected = game.players.count * r.fixtureIds.count
                if expected > 0 && r.predictions.count >= expected {
                    TutorialManager.shared.advance(to: .predictorCloseRound)
                }
            }
        case .predictorCloseRound:
            if closedCount == 1 {
                TutorialManager.shared.advance(to: .predictorShare)
            }

        default:
            break
        }
    }

    // MARK: - Manual next (informational steps)

    private func handleNext() {
        switch TutorialManager.shared.currentStep {
        case .lmsWelcome:       TutorialManager.shared.advance(to: .lmsPlayers)
        case .lmsPlayers:       TutorialManager.shared.advance(to: .lmsOpenRound1)
        case .lmsShareRound1:   TutorialManager.shared.advance(to: .lmsOpenRound2)
        case .lmsWinner:        exitTutorial()
        case .predictorWelcome: TutorialManager.shared.advance(to: .predictorPlayers)
        case .predictorPlayers: TutorialManager.shared.advance(to: .predictorOpenRound)
        case .predictorShare:   exitTutorial()
        default:                handleSkip()  // non-informational: skip = perform + advance
        }
    }

    // MARK: - Skip (perform data action programmatically then let state advance)

    private func handleSkip() {
        guard let game else { return }
        switch TutorialManager.shared.currentStep {
        case .lmsOpenRound1:
            TutorialDataService.openLMSRound1(in: game, context: context)
            try? context.save()

        case .lmsEnterPicks1:
            if let round = game.rounds.first(where: { $0.status == .open }) {
                TutorialDataService.assignLMSRound1Picks(game: game, round: round, context: context)
                try? context.save()
            }

        case .lmsEnterResults1:
            if let round = game.rounds.first(where: { $0.status == .open }) {
                TutorialDataService.closeLMSRound1(game: game, round: round, context: context)
                try? context.save()
            }

        case .lmsOpenRound2:
            TutorialDataService.openLMSRound2(in: game, context: context)
            try? context.save()

        case .lmsEnterPicks2:
            if let round = game.rounds.first(where: { $0.status == .open }) {
                TutorialDataService.assignLMSRound2Picks(game: game, round: round, context: context)
                try? context.save()
            }

        case .lmsEnterResults2:
            if let round = game.rounds.first(where: { $0.status == .open }) {
                TutorialDataService.closeLMSRound2AndDeclareWinner(game: game, round: round, context: context)
                try? context.save()
            }

        case .predictorOpenRound:
            TutorialDataService.openPredictorRound(in: game, context: context)
            try? context.save()

        case .predictorEnterPredictions:
            if let round = game.rounds.first(where: { $0.status == .open }) {
                TutorialDataService.seedPredictorPredictions(
                    game: game, round: round, userHome: 2, userAway: 0, context: context
                )
                try? context.save()
            }

        case .predictorCloseRound:
            if let round = game.rounds.first(where: { $0.status == .open }) {
                try? TutorialDataService.closePredictorRound(game: game, round: round, context: context)
                try? context.save()
            }

        default:
            break
        }
    }

    // MARK: - Exit

    private func exitTutorial() {
        TutorialManager.shared.end(context: context)
        try? context.save()
        dismiss()
    }
}
