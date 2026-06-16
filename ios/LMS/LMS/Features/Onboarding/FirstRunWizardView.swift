import SwiftUI
import SwiftData

/// A guided first-game walkthrough for new managers. It *drives the real screens*
/// (Players, New Game, Add Players, Open Round, Picks, Results, share cards) in
/// order — no duplicate logic — and reads live state to tick steps off. The
/// normal flow is untouched; this is purely an optional on-ramp.
struct FirstRunWizardView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("hasCompletedFirstRun") private var hasCompletedFirstRun = false
    @Query(sort: \Game.createdAt, order: .reverse) private var games: [Game]
    @Query private var roster: [RosterMember]

    @State private var stepIndex = 0
    @State private var activeSheet: WizardSheet?
    @State private var pendingResolve = false   // ResultsEntryView binding (unused here)

    // The wizard's game is simply the newest one (a first-run user has none yet).
    private var game: Game? { games.first }
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

    private var steps: [WizardStep] {
        [
            .init(sheet: .players, icon: "person.2.fill",
                  title: "Set up your players",
                  detail: "Add the people who'll play, and optionally group them (e.g. \"Office\"). This is your reusable roster.",
                  action: "Open Players", gated: true),
            .init(sheet: .newGame, icon: "trophy.fill",
                  title: "Create the game",
                  detail: "Name it, choose whether you're playing, and set anonymity for shared cards.",
                  action: "New Game", gated: true),
            .init(sheet: .addPlayers, icon: "person.badge.plus",
                  title: "Add players to the game",
                  detail: "Pull people from your roster into this game — you need at least two to play.",
                  action: "Add Players", gated: true),
            .init(sheet: .openRound, icon: "calendar.badge.plus",
                  title: "Open round 1",
                  detail: "Pick the fixtures this round runs on and set the picks deadline.",
                  action: "Open Round", gated: true),
            .init(sheet: .shareFixtures, icon: "square.and.arrow.up",
                  title: "Share the fixtures",
                  detail: "Send the fixtures card so players know the matches to choose from.",
                  action: "Share Fixtures Card", gated: false),
            .init(sheet: .picks, icon: "checklist",
                  title: "Enter & assign picks",
                  detail: "Record each player's team, then Auto-Assign anyone who didn't reply in time.",
                  action: "Enter Picks", gated: true),
            .init(sheet: .sharePicks, icon: "square.and.arrow.up",
                  title: "Share the picks",
                  detail: "Send the picks summary so everyone sees who picked what.",
                  action: "Share Picks Card", gated: false),
            .init(sheet: .results, icon: "flag.checkered",
                  title: "Enter results & close",
                  detail: "Pull the results (or set them), then close the round to work out who's out.",
                  action: "Enter Results", gated: true),
            .init(sheet: .shareResults, icon: "square.and.arrow.up",
                  title: "Share the results",
                  detail: "Send the results card — who survived to round 2. That's the loop! Carry on as normal from here.",
                  action: "Share Results Card", gated: false)
        ]
    }

    private func isComplete(_ index: Int) -> Bool {
        switch steps[index].sheet {
        case .players:       return !roster.isEmpty || (game?.players.isEmpty == false)
        case .newGame:       return game != nil
        case .addPlayers:    return (game?.activePlayers.count ?? 0) >= 2
        case .openRound:     return openRound != nil || latestClosedRound != nil
        case .picks:         return picksComplete || latestClosedRound != nil
        case .results:       return latestClosedRound != nil
        case .shareFixtures, .sharePicks, .shareResults: return true   // encouraged, not gated
        }
    }

    private var isLastStep: Bool { stepIndex == steps.count - 1 }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                ProgressView(value: Double(stepIndex), total: Double(steps.count - 1))
                    .padding(.top, 8)

                let step = steps[stepIndex]
                Spacer()
                VStack(spacing: 16) {
                    Image(systemName: step.icon)
                        .font(.system(size: 52))
                        .foregroundStyle(.tint)
                    Text("Step \(stepIndex + 1) of \(steps.count)")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text(LocalizedStringKey(step.title))
                        .font(.title2.bold()).multilineTextAlignment(.center)
                    Text(LocalizedStringKey(step.detail))
                        .font(.body).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    if step.gated && isComplete(stepIndex) {
                        Label("Done", systemImage: "checkmark.circle.fill")
                            .font(.subheadline).foregroundStyle(.green)
                    }
                }
                .padding(.horizontal, 28)
                Spacer()

                Button {
                    open(step.sheet)
                } label: {
                    Text(LocalizedStringKey(step.action)).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                HStack {
                    Button("Back") { if stepIndex > 0 { stepIndex -= 1 } }
                        .disabled(stepIndex == 0)
                    Spacer()
                    Button(isLastStep ? "Finish" : "Next") { advance() }
                        .disabled(steps[stepIndex].gated && !isComplete(stepIndex))
                }
                .padding(.horizontal, 4)
            }
            .padding()
            .navigationTitle("Guided Setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Exit") { dismiss() } }
            }
            .sheet(item: $activeSheet, onDismiss: autoAdvance) { which in
                sheetContent(which)
            }
        }
    }

    @ViewBuilder
    private func sheetContent(_ which: WizardSheet) -> some View {
        switch which {
        case .players:
            PlayersView()
        case .newGame:
            NewGameView()
        case .addPlayers:
            if let game { AddPlayersView(game: game) }
        case .openRound:
            if let game { OpenRoundView(game: game) }
        case .picks:
            if let game, let round = openRound { PicksEntryView(game: game, round: round) }
        case .results:
            if let game, let round = openRound {
                ResultsEntryView(game: game, round: round, pendingResolve: $pendingResolve)
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
        }
    }

    /// Opens a step's screen. Share-card steps cost a rewarded ad for free users —
    /// the same gate the real screens use (GameDetailView / PicksEntryView) — so
    /// the wizard isn't an ad-free side door to the shareable cards.
    private func open(_ which: WizardSheet) {
        if which.isShare {
            AdGate.run { activeSheet = which }
        } else {
            activeSheet = which
        }
    }

    /// After a step's screen closes, advance if that step is now satisfied.
    private func autoAdvance() {
        if isComplete(stepIndex) && !isLastStep { stepIndex += 1 }
    }

    private func advance() {
        if isLastStep {
            hasCompletedFirstRun = true
            dismiss()
        } else {
            stepIndex += 1
        }
    }
}

private struct WizardStep {
    let sheet: WizardSheet
    let icon: String
    let title: String
    let detail: String
    let action: String
    let gated: Bool
}

enum WizardSheet: String, Identifiable {
    case players, newGame, addPlayers, openRound, picks, results
    case shareFixtures, sharePicks, shareResults
    var id: String { rawValue }

    /// The steps that open a shareable summary card (rewarded-ad gated for free).
    var isShare: Bool {
        switch self {
        case .shareFixtures, .sharePicks, .shareResults: return true
        default: return false
        }
    }
}
