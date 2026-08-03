import SwiftUI
import SwiftData

/// Card restyle of `KillerPredictionsEntryView`. Same one-player-at-a-time
/// entry model — a Home/Draw/Away guess per Manager Picked Game, restyled as
/// `SelectablePill`s instead of a segmented `Picker` (same shape LMS's V2
/// Results screen already established). Kill Phase's hit-target picker
/// (`KillerHitTargetPickerViewV2`) has no Predictor equivalent — net-new V2
/// UI, not a mirror — restyled per-fixture, same as v1, rather than force-
/// fit into Predictor's single end-of-list Joker checkpoint (structurally
/// different: hit-target is per-fixture and phase-gated, Joker is one
/// global per-round choice).
struct KillerPredictionsEntryViewV2: View {
    @Environment(\.dismiss) private var dismiss
    let game: Game
    let round: Round

    @State private var data: LeagueData?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedPlayerId: UUID?
    @State private var showingPlayerPicker = false

    private var activePlayers: [Player] {
        game.players.filter { $0.status == .active }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var roundFixtures: [MatchDTO] {
        guard let data else { return [] }
        let ids = Set(round.fixtureIds)
        return data.matches.filter { ids.contains($0.id) }.sorted(by: MatchDTO.byKickoffThenId)
    }

    private var selectedPlayer: Player? {
        if let id = selectedPlayerId, let match = activePlayers.first(where: { $0.id == id }) { return match }
        return activePlayers.first { !slateComplete($0) } ?? activePlayers.first
    }

    private func slateComplete(_ player: Player) -> Bool {
        KillerScoringService.slateComplete(for: player, round: round, game: game)
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && data == nil {
                    ProgressView("Loading fixtures…")
                } else if let errorMessage, data == nil {
                    ContentUnavailableView("Couldn't load fixtures", systemImage: "wifi.slash", description: Text(errorMessage))
                } else if activePlayers.isEmpty {
                    ContentUnavailableView("No active players", systemImage: "person.slash")
                } else if let player = selectedPlayer {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            playerRow(current: player)
                            ForEach(roundFixtures) { fixture in
                                KillerFixturePredictionRowV2(
                                    game: game,
                                    player: player,
                                    round: round,
                                    fixture: fixture,
                                    teamsById: data?.teamsById ?? [:],
                                    isKillPhase: KillerScoringService.phase(for: round, game: game) == .kill
                                )
                            }
                        }
                        .padding(.horizontal, V2Theme.Spacing.horizontal)
                        .padding(.vertical, V2Theme.Spacing.section)
                    }
                    .sheet(isPresented: $showingPlayerPicker) {
                        KillerPlayerPickerSheetV2(players: activePlayers, isComplete: slateComplete, selectedId: $selectedPlayerId)
                    }
                }
            }
            .background(V2Theme.background.ignoresSafeArea())
            .v2Header("Round \(round.roundNumber)")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.foregroundStyle(V2Theme.Mode.killer)
                }
            }
            .task { await load() }
        }
    }

    private func playerRow(current: Player) -> some View {
        Button { showingPlayerPicker = true } label: {
            Card(padding: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        MicroLabel(text: "Player")
                        Text(current.name)
                            .font(V2Theme.Typography.rowTitle)
                            .foregroundStyle(V2Theme.textPrimary)
                    }
                    Spacer()
                    if slateComplete(current) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(V2Theme.accent)
                    }
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(V2Theme.textSecondary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            data = try await LeagueData.load(for: game.leagues)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

private struct KillerPlayerPickerSheetV2: View {
    @Environment(\.dismiss) private var dismiss
    let players: [Player]
    let isComplete: (Player) -> Bool
    @Binding var selectedId: UUID?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(players) { player in
                        Button {
                            selectedId = player.id
                            dismiss()
                        } label: {
                            HStack {
                                Text(player.name).foregroundStyle(V2Theme.textPrimary)
                                if isComplete(player) {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(V2Theme.accent)
                                }
                                Spacer()
                            }
                            .padding(12)
                            .background(V2Theme.pillBackground, in: RoundedRectangle(cornerRadius: V2Theme.Radius.row, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, V2Theme.Spacing.horizontal)
                .padding(.vertical, V2Theme.Spacing.section)
            }
            .background(V2Theme.background.ignoresSafeArea())
            .navigationTitle("Players")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}

private struct KillerFixturePredictionRowV2: View {
    @Environment(\.modelContext) private var context
    let game: Game
    let player: Player
    let round: Round
    let fixture: MatchDTO
    let teamsById: [Int: TeamDTO]
    let isKillPhase: Bool

    private var existing: KillerPrediction? {
        KillerScoringService.prediction(for: player, fixtureId: fixture.id, in: round)
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                FixtureLabel(fixture: fixture, teamsById: teamsById)
                    .foregroundStyle(V2Theme.textPrimary)
                HStack(spacing: 8) {
                    outcomePill(.homeWin, title: "Home")
                    outcomePill(.draw, title: "Draw")
                    outcomePill(.awayWin, title: "Away")
                }
                if isKillPhase && existing != nil {
                    KillerHitTargetPickerViewV2(game: game, player: player, round: round, fixtureId: fixture.id)
                }
            }
        }
    }

    private func outcomePill(_ outcome: FixtureOutcome, title: String) -> some View {
        SelectablePill(title: title, isSelected: existing?.predictedOutcome == outcome, tint: V2Theme.Mode.killer) {
            KillerScoringService.setPrediction(player: player, round: round, fixtureId: fixture.id, outcome: outcome, context: context)
        }
    }
}

/// Card restyle of `KillerHitTargetPickerView` — Kill Phase only, picks which
/// opponent this Manager Picked Game's prediction Hits. Already-used
/// opponents (by this player's other Hits this round) are excluded so a
/// duplicate target can't be picked. At exactly 2 active players there's
/// only one possible opponent, so the picker hides and auto-assigns it.
private struct KillerHitTargetPickerViewV2: View {
    @Environment(\.modelContext) private var context
    let game: Game
    let player: Player
    let round: Round
    let fixtureId: Int

    private var existing: KillerPrediction? {
        KillerScoringService.prediction(for: player, fixtureId: fixtureId, in: round)
    }

    private var otherActivePlayers: [Player] {
        game.players.filter { $0.status == .active && $0.id != player.id }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var usedElsewhere: Set<UUID> {
        Set(
            KillerScoringService.predictions(for: player, in: round)
                .filter { $0.fixtureId != fixtureId }
                .compactMap(\.hitTargetPlayerId)
        )
    }

    private var availableTargets: [Player] {
        otherActivePlayers.filter { !usedElsewhere.contains($0.id) }
    }

    var body: some View {
        Group {
            if otherActivePlayers.count > 1 {
                VStack(alignment: .leading, spacing: 6) {
                    MicroLabel(systemImage: "target", text: "Hit target", tint: V2Theme.danger)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(availableTargets) { opponent in
                                SelectablePill(
                                    title: opponent.name,
                                    isSelected: existing?.hitTargetPlayerId == opponent.id,
                                    tint: V2Theme.danger
                                ) { setTarget(opponent.id) }
                            }
                        }
                    }
                }
            }
        }
        .onAppear { autoAssignIfOnlyOpponent() }
    }

    private func setTarget(_ id: UUID) {
        KillerScoringService.setHitTarget(player: player, round: round, fixtureId: fixtureId, targetPlayerId: id, context: context)
    }

    private func autoAssignIfOnlyOpponent() {
        guard otherActivePlayers.count == 1, existing?.hitTargetPlayerId == nil,
              let onlyOpponent = otherActivePlayers.first else { return }
        setTarget(onlyOpponent.id)
    }
}
