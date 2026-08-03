import SwiftUI
import SwiftData

/// Card restyle of `PredictionsEntryView`: same one-player-at-a-time entry
/// model (a segmented picker of players, one score row per fixture), styled
/// as compact fixture cards per the PWA redesign brief's Predictor layout
/// (scrollable rows, team names once, compact score entry, `J` joker
/// button). Data loading is shared with the original via
/// `PredictionsEntryStore` — see that file's doc comment; nothing else about
/// the original view is touched.
struct PredictionsEntryViewV2: View {
    @Environment(\.dismiss) private var dismiss
    let game: Game
    let round: Round

    @State private var store = PredictionsEntryStore()
    @State private var selectedPlayerId: UUID?
    @State private var showingPlayerPicker = false
    @State private var jokerExpanded = false
    @State private var pendingJokerFixtureId: Int?
    /// Which fixture card is flashing red, plus a nonce so re-tapping the
    /// Joker checkpoint while still incomplete re-triggers the flicker even
    /// if it's the same fixture as last time (an `Int?` alone wouldn't
    /// change value, so `onChange` wouldn't fire again).
    @State private var flicker: FlickerRequest?

    private struct FlickerRequest: Equatable {
        let fixtureId: Int
        let nonce: Int
    }

    private var activePlayers: [Player] {
        game.players.filter { $0.status == .active }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Defaults to the first alphabetical player with no submission yet
    /// (0 predictions) rather than just the first player, so opening this
    /// screen lands the manager straight on someone who still needs entry
    /// instead of re-showing whoever's alphabetically first regardless of
    /// progress. Falls back to the first not-yet-fully-complete player, then
    /// to the first player outright once everyone's done.
    private var selectedPlayer: Player? {
        if let id = selectedPlayerId, let match = activePlayers.first(where: { $0.id == id }) { return match }
        return activePlayers.first { PredictorScoringService.predictions(for: $0, in: round).isEmpty }
            ?? activePlayers.first { !isFullyComplete($0) }
            ?? activePlayers.first
    }

    private func slateComplete(_ player: Player) -> Bool {
        PredictorScoringService.slateComplete(for: player, round: round)
    }

    /// "Complete" for the tick shown against a player's name — every fixture
    /// scored AND (when Joker is enabled for this game) a Joker actually
    /// chosen, not just left unset.
    private func isFullyComplete(_ player: Player) -> Bool {
        guard slateComplete(player) else { return false }
        guard game.predictorJokerEnabled else { return true }
        return PredictorScoringService.predictions(for: player, in: round).contains { $0.isJoker }
    }

    /// The single source of truth for "done" everywhere in this screen
    /// (Unassigned filter, Joker gating, completion ticks): a real,
    /// persisted `Prediction` row exists. Nothing is fabricated on the way
    /// to that — see `FixturePredictionRowV2`'s pending-until-both-sides
    /// local state, which is what makes this simple check correct instead
    /// of the touched-sides workaround this replaced.
    private func isEntered(_ player: Player, _ fixture: MatchDTO) -> Bool {
        PredictorScoringService.prediction(for: player, fixtureId: fixture.id, in: round) != nil
    }

    private func fixtureLabel(_ fixture: MatchDTO) -> String {
        let teamsById = store.data?.teamsById ?? [:]
        let home = teamsById[fixture.homeTeamId]?.shortName ?? teamsById[fixture.homeTeamId]?.name ?? "Team \(fixture.homeTeamId)"
        let away = teamsById[fixture.awayTeamId]?.shortName ?? teamsById[fixture.awayTeamId]?.name ?? "Team \(fixture.awayTeamId)"
        return "\(home) v \(away)"
    }

    private func fixtureLabelWithScore(_ fixture: MatchDTO, player: Player) -> String {
        let pred = PredictorScoringService.prediction(for: player, fixtureId: fixture.id, in: round)
        guard let pred else { return "\(fixtureLabel(fixture)) — no score" }
        return "\(fixtureLabel(fixture))  (\(pred.predictedHome)-\(pred.predictedAway))"
    }

    private func currentJokerFixture(for player: Player) -> MatchDTO? {
        guard let jokered = PredictorScoringService.predictions(for: player, in: round).first(where: { $0.isJoker }) else { return nil }
        return store.fixtures.first { $0.id == jokered.fixtureId }
    }

    /// Tapping the Joker checkpoint while any fixture is still missing a
    /// score doesn't open the picker — it flashes the *first* incomplete
    /// card red instead, the same "show, don't block with a message"
    /// treatment as picking an unscored fixture used to do.
    private func openJokerOrFlickerFirstIncomplete(player: Player) {
        if let first = store.fixtures.first(where: { !isEntered(player, $0) }) {
            flicker = FlickerRequest(fixtureId: first.id, nonce: (flicker?.nonce ?? 0) + 1)
            return
        }
        pendingJokerFixtureId = currentJokerFixture(for: player)?.id
        jokerExpanded = true
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.isLoading && store.data == nil {
                    ProgressView("Loading fixtures…")
                } else if let errorMessage = store.errorMessage, store.data == nil {
                    ContentUnavailableView("Couldn't load fixtures", systemImage: "wifi.slash", description: Text(errorMessage))
                } else if activePlayers.isEmpty {
                    ContentUnavailableView("No active players", systemImage: "person.slash")
                } else if let player = selectedPlayer {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                playerRow(current: player)
                                ForEach(store.fixtures) { fixture in
                                    FixturePredictionRowV2(
                                        player: player,
                                        round: round,
                                        fixture: fixture,
                                        teamsById: store.data?.teamsById ?? [:],
                                        isJokerFixture: fixture.id == currentJokerFixture(for: player)?.id,
                                        flickerRed: fixture.id == flicker?.fixtureId,
                                        flickerNonce: flicker?.nonce ?? 0
                                    )
                                    // Keyed on player too, not just fixture — switching the
                                    // selected player must reset each row's local
                                    // pending-score state, not carry over the previous
                                    // player's half-entered values.
                                    .id("\(player.id)-\(fixture.id)")
                                }
                                // At the end of the list — reached only after the
                                // fixtures above, matching how it's actually used
                                // (last step, once scores are in).
                                if game.predictorJokerEnabled { jokerCard(player: player) }
                            }
                            .padding(.horizontal, V2Theme.Spacing.horizontal)
                            .padding(.vertical, V2Theme.Spacing.section)
                        }
                        .onChange(of: flicker) { _, new in
                            guard let id = new?.fixtureId else { return }
                            withAnimation { proxy.scrollTo(id, anchor: .center) }
                        }
                    }
                    .sheet(isPresented: $showingPlayerPicker) {
                        PlayerPickerSheetV2(
                            players: activePlayers,
                            isComplete: isFullyComplete,
                            predictionCount: { PredictorScoringService.predictions(for: $0, in: round).count },
                            selectedId: $selectedPlayerId
                        )
                    }
                }
            }
            .background(V2Theme.background.ignoresSafeArea())
            .v2Header("Round \(round.roundNumber)")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(V2Theme.accent)
                }
            }
            .task { await store.load(game: game, round: round) }
        }
    }

    /// A single tappable row opening a searchable picker, rather than a
    /// horizontally-scrolling pill list — scanning/scrolling past 100+ names
    /// to find one is the thing that made the pill row unusable at scale.
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
                    if isFullyComplete(current) {
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

    /// The Joker "checkpoint" — a single card at the end of the list rather
    /// than a control on every fixture card. Collapsed, it's a summary +
    /// tap target; tapping it either flickers the first incomplete fixture
    /// (see `openJokerOrFlickerFirstIncomplete`) or expands into a
    /// scores-shown picker with an explicit Confirm, so setting the Joker is
    /// a deliberate last step rather than an instant tap that could land on
    /// the wrong fixture.
    private func jokerCard(player: Player) -> some View {
        let current = currentJokerFixture(for: player)
        return Card(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                MicroLabel(systemImage: "star.fill", text: "Joker", tint: V2Theme.warning)
                if jokerExpanded {
                    VStack(spacing: 8) {
                        ForEach(store.fixtures) { fixture in
                            let isPending = pendingJokerFixtureId == fixture.id
                            Button { pendingJokerFixtureId = fixture.id } label: {
                                HStack {
                                    Text(fixtureLabelWithScore(fixture, player: player))
                                        .font(.subheadline)
                                        .foregroundStyle(V2Theme.textPrimary)
                                        .lineLimit(1)
                                    Spacer()
                                    if isPending {
                                        Image(systemName: "checkmark.circle.fill").foregroundStyle(V2Theme.warning)
                                    }
                                }
                                .padding(10)
                                .background(
                                    isPending ? V2Theme.highlightBackground : V2Theme.pillBackground,
                                    in: RoundedRectangle(cornerRadius: V2Theme.Radius.row, style: .continuous)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                        HStack(spacing: 10) {
                            if current != nil {
                                Button("Clear") {
                                    PredictorScoringService.clearJoker(player: player, round: round)
                                    jokerExpanded = false
                                }
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(V2Theme.danger)
                            }
                            Spacer()
                            Button("Cancel") { jokerExpanded = false }
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(V2Theme.textSecondary)
                            Button("Confirm") {
                                if let id = pendingJokerFixtureId {
                                    PredictorScoringService.setJoker(player: player, round: round, fixtureId: id)
                                }
                                jokerExpanded = false
                            }
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(V2Theme.accentOnAccent)
                            .padding(.horizontal, 16).padding(.vertical, 8)
                            .background(V2Theme.warning, in: RoundedRectangle(cornerRadius: V2Theme.Radius.pill, style: .continuous))
                            .disabled(pendingJokerFixtureId == nil)
                            .opacity(pendingJokerFixtureId == nil ? 0.4 : 1)
                        }
                    }
                } else {
                    Button { openJokerOrFlickerFirstIncomplete(player: player) } label: {
                        HStack {
                            Text(current.map(fixtureLabel) ?? "No joker selected")
                                .foregroundStyle(current != nil ? V2Theme.textPrimary : V2Theme.textSecondary)
                                .lineLimit(1)
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(V2Theme.textSecondary)
                        }
                        .padding(12)
                        .background(V2Theme.pillBackground, in: RoundedRectangle(cornerRadius: V2Theme.Radius.row, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct PlayerPickerSheetV2: View {
    let players: [Player]
    let isComplete: (Player) -> Bool
    /// How many fixtures this player already has a score for — 0 means
    /// "hasn't started", the case the manager most needs to triage on a big
    /// roster (chasing stragglers). Kept to one extra filter pill, not a
    /// separate tab/section, per "keep it usable."
    let predictionCount: (Player) -> Int
    @Binding var selectedId: UUID?
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var notStartedOnly = false

    private var notStartedCount: Int { players.filter { predictionCount($0) == 0 }.count }

    private var filtered: [Player] {
        var result = players
        if notStartedOnly { result = result.filter { predictionCount($0) == 0 } }
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { result = result.filter { $0.name.localizedCaseInsensitiveContains(trimmed) } }
        return result
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    SelectablePill(title: "All (\(players.count))", isSelected: !notStartedOnly, tint: V2Theme.Mode.predictor) {
                        notStartedOnly = false
                    }
                    SelectablePill(title: "Not started (\(notStartedCount))", isSelected: notStartedOnly, tint: V2Theme.Mode.predictor) {
                        notStartedOnly = true
                    }
                    Spacer()
                }
                .padding(.horizontal, V2Theme.Spacing.horizontal)
                .padding(.vertical, 10)

                if filtered.isEmpty {
                    ContentUnavailableView("No players", systemImage: "person.slash")
                } else {
                    List(filtered) { player in
                        Button {
                            selectedId = player.id
                            dismiss()
                        } label: {
                            HStack {
                                Text(player.name).foregroundStyle(V2Theme.textPrimary)
                                Spacer()
                                if isComplete(player) {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(V2Theme.accent)
                                } else if predictionCount(player) == 0 {
                                    Text("Not started").font(.caption).foregroundStyle(V2Theme.textTertiary)
                                }
                            }
                        }
                        .listRowBackground(V2Theme.cardBackground)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(V2Theme.background.ignoresSafeArea())
            .searchable(text: $query, prompt: "Search players")
            .v2Header("Choose Player")
        }
    }
}

private struct FixturePredictionRowV2: View {
    @Environment(\.modelContext) private var context
    let player: Player
    let round: Round
    let fixture: MatchDTO
    let teamsById: [Int: TeamDTO]
    /// Read-only now — Joker is set from the one dropdown in `jokerCard`,
    /// not a per-card button; this just marks which card it landed on.
    let isJokerFixture: Bool
    /// True for one card at a time — the manager tried to open the Joker
    /// checkpoint while this fixture was still missing a score, and it's
    /// flashing red instead of a blocking message.
    let flickerRed: Bool
    /// Bumped on every flicker request, including repeats on the same
    /// fixture, so `onChange(of:)` re-fires even when `flickerRed` doesn't
    /// change value (already true → true wouldn't otherwise trigger again).
    let flickerNonce: Int

    @State private var flickerOpacity: Double = 0

    /// Not-yet-saved taps for this fixture. Nothing is written to SwiftData
    /// until BOTH sides have a real value (from a fresh tap here, or
    /// already-saved from a prior session) — see `commitIfReady`. This is
    /// the actual fix: earlier attempts tried to reconstruct "is this side
    /// deliberate" *after* both sides were already written with one
    /// defaulted to 0, which is exactly the information that gets lost by
    /// writing early. Not writing early removes the need to reconstruct it.
    @State private var pendingHome: Int?
    @State private var pendingAway: Int?

    private var existing: Prediction? {
        PredictorScoringService.prediction(for: player, fixtureId: fixture.id, in: round)
    }
    /// Real value if either this session touched it, or it was already
    /// saved from before — nil means genuinely never given a value.
    private var home: Int? { pendingHome ?? existing?.predictedHome }
    private var away: Int? { pendingAway ?? existing?.predictedAway }

    private func name(_ id: Int) -> String {
        teamsById[id]?.shortName ?? teamsById[id]?.name ?? "Team \(id)"
    }
    private var kickoff: Date? { FixtureFormat.kickoffDate(fixture.kickoff) }

    var body: some View {
        Card(padding: 14) {
            VStack(spacing: 10) {
                HStack {
                    if let kickoff {
                        Text(kickoff, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())
                            .font(.caption2)
                            .foregroundStyle(V2Theme.textTertiary)
                    }
                    Spacer()
                    if isJokerFixture {
                        Label("Joker", systemImage: "star.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(V2Theme.warning)
                    }
                }

                teamScoreRow(name: name(fixture.homeTeamId), value: home, idPrefix: "predictionHomeV2-\(fixture.id)", team: AppString("Home")) {
                    pendingHome = $0
                    commitIfReady()
                }
                teamScoreRow(name: name(fixture.awayTeamId), value: away, idPrefix: "predictionAwayV2-\(fixture.id)", team: AppString("Away")) {
                    pendingAway = $0
                    commitIfReady()
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: V2Theme.Radius.card, style: .continuous)
                .stroke(V2Theme.danger.opacity(flickerOpacity), lineWidth: 3)
        )
        .onChange(of: flickerNonce) { _, _ in
            guard flickerRed else { return }
            flickerOpacity = 0
            withAnimation(.easeInOut(duration: 0.15).repeatCount(6, autoreverses: true)) {
                flickerOpacity = 1
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                withAnimation(.easeInOut(duration: 0.2)) { flickerOpacity = 0 }
            }
        }
    }

    private func teamScoreRow(name: String, value: Int?, idPrefix: String, team: String, onChange: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 10) {
            Text(name)
                .font(V2Theme.Typography.rowTitle)
                .foregroundStyle(V2Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 4) {
                Button { onChange(max(0, (value ?? 0) - 1)) } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 26))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityIdentifier("\(idPrefix)-minus")
                .accessibilityLabel("Decrease \(team) score")

                // Blank ("–") until this side has a real value — nil, not a
                // fabricated 0 — so an untouched fixture never looks
                // identical to a deliberate 0-0.
                Text(value.map { "\($0)" } ?? "–")
                    .font(.title2.weight(.bold).monospacedDigit())
                    .foregroundStyle(value != nil ? V2Theme.textPrimary : V2Theme.textTertiary)
                    .frame(width: 28)
                    .accessibilityLabel(value.map { "\(team) score: \($0)" } ?? "\(team) score: not entered")

                Button { onChange((value ?? 0) + 1) } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 26))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityIdentifier("\(idPrefix)-plus")
                .accessibilityLabel("Increase \(team) score")
            }
            .foregroundStyle(V2Theme.Mode.predictor)
            .buttonStyle(.plain)
        }
    }

    /// Writes to SwiftData only once both sides have a real value — from a
    /// tap just now, or already saved from a prior session. Editing an
    /// already-complete fixture (both sides already real) writes on every
    /// tap as before; only a fixture with no history at all withholds the
    /// write while it's still half-entered.
    private func commitIfReady() {
        guard let h = home, let a = away else { return }
        PredictorScoringService.setPrediction(
            player: player, round: round, fixtureId: fixture.id, home: h, away: a, context: context
        )
    }
}
