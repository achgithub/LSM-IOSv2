import SwiftUI
import SwiftData

/// Manual texted-picks workflow: the manager pastes one player's raw
/// shorthand text (e.g. "1H 2A 3D" or, in the Kill Phase, "1H2 2A4 3D1"),
/// previews the parsed picks, and confirms to commit them — an alternate
/// entry mode alongside manual tap-picking in `KillerPredictionsEntryView`/
/// `KillerHitTargetPickerView`, not a replacement (the manager can still tap
/// through for players who don't text picks in). One player per paste, per
/// the confirmed scratchpad design.
struct KillerScratchpadEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let game: Game
    let round: Round

    @State private var data: LeagueData?
    @State private var selectedPlayerId: UUID?
    @State private var text: String = ""
    @State private var parsedPicks: [ParsedKillerPick] = []
    @State private var errorMessage: String?
    @State private var confirmedCount: Int?

    private var phase: KillerPhase { KillerScoringService.phase(for: round, game: game) }

    private var activePlayers: [Player] {
        game.players.filter { $0.status == .active }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var selectedPlayer: Player? {
        activePlayers.first { $0.id == selectedPlayerId } ?? activePlayers.first
    }

    /// Kickoff-sorted, matching `round.fixtureIds`' stored order (see
    /// `KillerOpenRoundView.create`) — the same numbering the `.fixtures`
    /// share card uses.
    private var roundFixtures: [MatchDTO] {
        guard let data else { return [] }
        let ids = Set(round.fixtureIds)
        return data.matches.filter { ids.contains($0.id) }.sorted(by: MatchDTO.byKickoffThenId)
    }

    private var fixtureNumberToId: [Int: Int] {
        Dictionary(uniqueKeysWithValues: roundFixtures.enumerated().map { ($0 + 1, $1.id) })
    }

    /// Numbered alphabetically over active players — matches the
    /// `.playerKey` share card's numbering exactly.
    private var playerNumberToId: [Int: UUID] {
        Dictionary(uniqueKeysWithValues:
            game.activePlayers
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                .enumerated()
                .map { ($0 + 1, $1.id) }
        )
    }

    private func playerName(for id: UUID) -> String {
        game.players.first { $0.id == id }?.name ?? "?"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Player") {
                    Picker("Player", selection: Binding(
                        get: { selectedPlayerId ?? selectedPlayer?.id },
                        set: {
                            selectedPlayerId = $0
                            parsedPicks = []
                            errorMessage = nil
                            confirmedCount = nil
                        }
                    )) {
                        ForEach(activePlayers) { p in Text(p.name).tag(Optional(p.id)) }
                    }
                    .pickerStyle(.menu)
                }

                Section("Paste picks") {
                    TextEditor(text: $text)
                        .frame(minHeight: 80)
                        .font(.system(.body, design: .monospaced))
                    Text(phase == .kill
                         ? "Format: fixture + H/D/A + target number, e.g. \"1H2 2A4 3D1\""
                         : "Format: fixture + H/D/A, e.g. \"1H 2A 3D\"")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Parse") { parse() }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedPlayer == nil)
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }

                if let confirmedCount {
                    Section {
                        Label(confirmedCount == 1
                              ? AppString("Saved \(confirmedCount) pick for \(selectedPlayer?.name ?? "").")
                              : AppString("Saved \(confirmedCount) picks for \(selectedPlayer?.name ?? "")."),
                              systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }

                if !parsedPicks.isEmpty {
                    Section("Preview") {
                        ForEach(parsedPicks, id: \.fixtureNumber) { pick in
                            HStack {
                                Text("Fixture \(pick.fixtureNumber)")
                                Spacer()
                                Text(pick.outcome.label)
                                if let targetId = pick.targetPlayerId {
                                    Text("→ \(playerName(for: targetId))").foregroundStyle(.secondary)
                                }
                            }
                            .font(.subheadline)
                        }
                        Button("Confirm") { confirm() }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle("Scratchpad")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
            .task { data = try? await LeagueData.load(for: game.leagues) }
        }
    }

    private func parse() {
        guard let player = selectedPlayer else { return }
        confirmedCount = nil
        let result = KillerPickTextParser.parse(
            text,
            phase: phase,
            fixtureCount: roundFixtures.count,
            playerNumberToId: playerNumberToId,
            selfPlayerId: player.id
        )
        switch result {
        case .success(let picks):
            parsedPicks = picks
            errorMessage = nil
        case .failure(let error):
            parsedPicks = []
            errorMessage = error.errorDescription
        }
    }

    private func confirm() {
        guard let player = selectedPlayer else { return }
        for pick in parsedPicks {
            guard let fixtureId = fixtureNumberToId[pick.fixtureNumber] else { continue }
            KillerScoringService.setPrediction(
                player: player, round: round, fixtureId: fixtureId, outcome: pick.outcome, context: context
            )
            if let targetId = pick.targetPlayerId {
                KillerScoringService.setHitTarget(
                    player: player, round: round, fixtureId: fixtureId, targetPlayerId: targetId, context: context
                )
            }
        }
        try? context.save()
        confirmedCount = parsedPicks.count
        text = ""
        parsedPicks = []
    }
}
