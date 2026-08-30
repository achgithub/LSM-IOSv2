import SwiftUI

/// One game's card row — extracted from `GamesPortalViewV2` so it can be
/// reused by Home's Favourites section as well as the Games screen's
/// per-mode sections. Mode-agnostic: computes its own manager-facing status
/// and standing preview from the shared scoring services, so it can't drift
/// from the real share-card numbers.
///
/// Leads with a Next Up action (see `NextUpStep`) rather than just status —
/// this app is "appifying a spreadsheet," not running a strict workflow
/// engine, so Next Up is a best-guess nudge read off the clock and cached
/// fixture data, not a hard gate; the manager can always ignore it and drill
/// into the game name instead, which is its own separate tap target into
/// the full detail screen. No per-row "resume wizard" button any more —
/// the Games portal's WIZARD tile's own Continue Game step (see
/// `GameWizardViewV2`) covers jumping into a specific game's wizard now, so
/// this row doesn't need a second entry point into it.
struct GameSummaryRow: View {
    let game: Game

    @Environment(Entitlements.self) private var entitlements
    @AppStorage("pwaSubmissionsEnabled") private var pwaSubmissionsEnabled = false
    @State private var leagueData: LeagueData?
    @State private var sheet: RowSheet?

    private var managerStatus: ManagerRoundStatus? { ManagerRoundStatus.make(for: game, data: leagueData) }
    private var modeColor: Color { V2Theme.Mode.color(for: game.mode) }
    private var roundContext: V2GameRoundContext { V2GameRoundContext(game: game) }
    private var pwaEnabled: Bool { entitlements.canUseCloud && pwaSubmissionsEnabled && game.cloudGameToken != nil }
    private var nextUp: NextUpStep { NextUpStep.make(for: game, data: leagueData, pwaEnabled: pwaEnabled) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: V2Theme.Mode.icon(for: game.mode))
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(modeColor)
                    .frame(width: 42, height: 42)
                    .background(modeColor.opacity(0.15), in: RoundedRectangle(cornerRadius: V2Theme.Radius.pill, style: .continuous))

                // The one tap target into the full detail screen (see this
                // file's top doc comment) — everything else on the row
                // either executes a Next Up step directly or toggles state
                // in place.
                NavigationLink {
                    destination
                } label: {
                    HStack(spacing: 4) {
                        VStack(alignment: .leading, spacing: 2) {
                            MicroLabel(text: V2Theme.Mode.displayName(for: game.mode), tint: modeColor)
                            Text(game.name)
                                .font(.system(.headline, design: V2Theme.Mode.fontDesign(for: game.mode)).weight(.bold))
                                .foregroundStyle(V2Theme.textPrimary)
                                .lineLimit(1)
                        }
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(V2Theme.textTertiary)
                    }
                }
                .buttonStyle(.plain)

                Spacer(minLength: 8)
                Button {
                    game.isFavourite.toggle()
                } label: {
                    Image(systemName: game.isFavourite ? "star.fill" : "star")
                        .font(.body)
                        .foregroundStyle(game.isFavourite ? V2Theme.warning : V2Theme.textTertiary)
                }
                .buttonStyle(.plain)
            }

            if let managerStatus {
                HStack(spacing: 8) {
                    V2StatusBadge(label: managerStatus.label, tint: managerStatus.tint)
                    if !managerStatus.detail.isEmpty {
                        Text(managerStatus.detail)
                            .font(.caption)
                            .foregroundStyle(V2Theme.textSecondary)
                    }
                }
                if let progress = managerStatus.submissionProgress {
                    ProgressView(value: progress)
                        .tint(modeColor)
                        .padding(.top, 2)
                }
            } else {
                V2StatusBadge(label: "Complete", tint: V2Theme.textSecondary)
            }

            Text(detailLine)
                .font(.caption)
                .foregroundStyle(V2Theme.textSecondary)

            nextUpRow
        }
        .padding(14)
        .v2FloatingCard()
        // Only needed once the round's past its deadline (that's the only
        // branch of `NextUpStep` that reads fixture status at all) — reading
        // cache-only via `LeagueData.load` per `LeagueData`'s own policy, so
        // this never spends a live fetch just because the portal's on
        // screen. Re-reads every 60s while matches are actually in progress
        // (not a fetch — `LeagueData.load` is cache-only — just re-checking
        // the on-disk cache) so the "X of Y in" count above visibly ticks up
        // as `SyncScheduler` (see docs/sync-refresh-policy.md) refreshes
        // that same cache from Home in the background; stops the moment
        // every fixture's in, since there's nothing left to change until
        // the round closes.
        .task(id: roundContext.currentRound?.id) {
            guard let round = roundContext.currentRound, round.status != .closed, Date() >= round.deadline else { return }
            while !Task.isCancelled {
                leagueData = try? await LeagueData.load(for: game.leagues)
                // Keep polling through `.confirmEntries` (deadline passed,
                // kickoff hasn't) too, not just `.matchesInProgress` —
                // otherwise this would poll once, see kickoff hasn't
                // happened yet, and stop for good since the round id (this
                // task's identity) doesn't change again until the round
                // closes. Any other phase (`.processResults`/`.none`/etc.)
                // means there's nothing left for a fixture-status re-read to
                // change, so stop there.
                switch NextUpStep.make(for: game, data: leagueData, pwaEnabled: pwaEnabled) {
                case .confirmEntries, .matchesInProgress:
                    try? await Task.sleep(for: .seconds(60))
                case .addPlayers, .openRound, .enterPicks, .processResults, .none:
                    return
                }
            }
        }
        .sheet(item: $sheet) { which in
            switch which {
            case .picks(let startFilteredToUnassigned):
                if let round = roundContext.openRound { picksDestination(round: round, startFilteredToUnassigned: startFilteredToUnassigned) }
            case .submissionQueue:
                SubmissionInboxViewV2(filterGameToken: game.cloudGameToken)
            case .shareLastRound:
                if let round = roundContext.latestClosedRound { shareLastRoundDestination(round: round) }
            }
        }
    }

    @ViewBuilder
    private var nextUpRow: some View {
        switch nextUp {
        case .none:
            EmptyView()
        case .addPlayers:
            HStack(spacing: 8) {
                NavigationLink {
                    addPlayersDestination
                } label: {
                    nextUpLabel(title: "Assign Players", icon: "person.badge.plus", tint: modeColor)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 2)
        case .openRound:
            HStack(spacing: 8) {
                NavigationLink {
                    openRoundDestination
                } label: {
                    nextUpLabel(title: "Open Round", icon: "play.circle.fill", tint: modeColor)
                }
                .buttonStyle(.plain)
                if roundContext.latestClosedRound != nil { shareButton }
            }
            .padding(.top, 2)
        case .enterPicks(let pwa):
            nextUpButton(title: pwa ? "Check Submission Queue" : "Enter Picks", icon: "square.and.pencil") {
                sheet = pwa ? .submissionQueue : .picks()
            }
        case .confirmEntries(let pwa, _, _):
            // Fixture count intentionally not shown here — that lives only
            // on Home's Favourites card (`FavouriteGameCard`), per Andrew:
            // the portal/games list is for managing a game, Favourites is
            // the at-a-glance surface. `finished`/`total` are still read
            // out of the payload elsewhere (nothing needs discarding at
            // the `RoundPhase`/`NextUpStep` level — see those types), just
            // not rendered on this row.
            nextUpButton(title: "Confirm Entries", icon: "checkmark.seal") {
                sheet = pwa ? .submissionQueue : .picks(startFilteredToUnassigned: game.mode == .lms)
            }
        case .matchesInProgress:
            // Same as `.confirmEntries` above — count shown on Home's
            // Favourites card only, not here.
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "sportscourt")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(V2Theme.textSecondary)
                    Text("Matches playing")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(V2Theme.textSecondary)
                    Spacer()
                    if roundContext.latestClosedRound != nil { shareButton }
                }
                unsubmittedReminder
            }
            .padding(.top, 2)
        case .processResults:
            HStack(spacing: 8) {
                NavigationLink {
                    resultsDestination
                } label: {
                    nextUpLabel(title: "Process Results", icon: "checkmark.circle.fill", tint: modeColor)
                }
                .buttonStyle(.plain)
                if roundContext.latestClosedRound != nil { shareButton }
            }
            .padding(.top, 2)
        }
    }

    /// Once matches kick off, `NextUpStep` stops mentioning missing picks at
    /// all (it's purely match-progress from there) — but a manager can still
    /// remember a pick someone texted them mid-round, so this keeps the
    /// reminder alive alongside "Matches playing." Never a gate: tapping it
    /// just opens the same picks sheet, jumped to the stragglers for LMS.
    @ViewBuilder
    private var unsubmittedReminder: some View {
        if let missing = managerStatus?.missingCount, missing > 0 {
            Button {
                sheet = .picks(startFilteredToUnassigned: game.mode == .lms)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.bubble")
                    Text(missing == 1 ? "1 unsubmitted" : "\(missing) unsubmitted")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(V2Theme.warning)
            }
            .buttonStyle(.plain)
        }
    }

    private func nextUpButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Button(action: action) {
                nextUpLabel(title: title, icon: icon, tint: modeColor)
            }
            .buttonStyle(.plain)
            if roundContext.latestClosedRound != nil { shareButton }
        }
        .padding(.top, 2)
    }

    private func nextUpLabel(title: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text("Next: \(title)")
        }
        .font(.caption.weight(.bold))
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(tint.opacity(0.14), in: Capsule())
    }

    private var shareButton: some View {
        Button { sheet = .shareLastRound } label: {
            Image(systemName: "square.and.arrow.up")
                .font(.caption.weight(.semibold))
                .foregroundStyle(V2Theme.textTertiary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Share last round")
    }

    @ViewBuilder
    private func picksDestination(round: Round, startFilteredToUnassigned: Bool = false) -> some View {
        switch game.mode {
        case .lms: PicksEntryViewV2(game: game, round: round, startFilteredToUnassigned: startFilteredToUnassigned)
        case .predictor: PredictionsEntryViewV2(game: game, round: round)
        case .killer: KillerPredictionsEntryViewV2(game: game, round: round)
        }
    }

    /// Only ever the *previous* round's result — LMS/Predictor/Killer's own
    /// "weekly results"/"results" card type, not a fixtures/entry-closed
    /// card; those are still one tap away inside the full detail screen.
    @ViewBuilder
    private func shareLastRoundDestination(round: Round) -> some View {
        switch game.mode {
        case .lms: SummaryShareView(game: game, round: round, type: .results)
        case .predictor: PredictorShareView(game: game, round: round, type: .weeklyResults)
        case .killer: KillerShareView(game: game, round: round, type: .weeklyResults)
        }
    }

    @ViewBuilder
    private var destination: some View {
        switch game.mode {
        case .lms: GameDetailViewV2(game: game)
        case .predictor: PredictorGameDetailViewV2(game: game)
        case .killer: KillerGameDetailViewV2(game: game)
        }
    }

    /// Same as `destination`, but lands with the results sheet already open
    /// — Process Results goes through the full detail screen rather than
    /// presenting `ResultsEntryViewV2` straight from this row, so closing a
    /// round still runs through each mode's own completion/tie-resolution
    /// handling (LMS especially — see `GameDetailViewV2`'s
    /// `pendingResolve`/`showResolve` chain) instead of a second, thinner
    /// copy of it living here.
    @ViewBuilder
    private var resultsDestination: some View {
        switch game.mode {
        case .lms: GameDetailViewV2(game: game, autoOpenSheet: .results)
        case .predictor: PredictorGameDetailViewV2(game: game, autoOpenSheet: .results)
        case .killer: KillerGameDetailViewV2(game: game, autoOpenSheet: .results)
        }
    }

    /// Same as `destination`, but lands with the add-players sheet already
    /// open — for `.addPlayers`, a game that doesn't have enough eligible
    /// players yet to open its first round.
    @ViewBuilder
    private var addPlayersDestination: some View {
        switch game.mode {
        case .lms: GameDetailViewV2(game: game, autoShowAddPlayers: true)
        case .predictor: PredictorGameDetailViewV2(game: game, autoShowAddPlayers: true)
        case .killer: KillerGameDetailViewV2(game: game, autoShowAddPlayers: true)
        }
    }

    /// Same as `destination`, but lands with the open-round sheet already
    /// open — for `.openRound`, a game with enough players and either no
    /// round yet or its last one closed.
    @ViewBuilder
    private var openRoundDestination: some View {
        switch game.mode {
        case .lms: GameDetailViewV2(game: game, autoOpenSheet: .open)
        case .predictor: PredictorGameDetailViewV2(game: game, autoOpenSheet: .open)
        case .killer: KillerGameDetailViewV2(game: game, autoOpenSheet: .open)
        }
    }

    /// One compact line summarizing the game's current standing — full
    /// per-player breakdown lives one tap away on `destination`, matching
    /// the slimmer POC card (icon/name/detail, no inline mini-leaderboard).
    private var detailLine: String {
        let round = game.currentRound
        switch game.mode {
        case .lms:
            let roundPart = round.map { "Round \($0.roundNumber) · " } ?? ""
            return "\(roundPart)\(game.activePlayers.count) still standing"
        case .predictor:
            let roundPart = round.map { "Matchday \($0.roundNumber) · " } ?? ""
            if let leader = PredictorStandings.leaderName(for: game) {
                return "\(roundPart)Leading: \(leader)"
            }
            return "\(roundPart)\(game.players.count) players"
        case .killer:
            let roundPart = round.map { "Round \($0.roundNumber) · " } ?? ""
            return "\(roundPart)\(game.activePlayers.count) players remain"
        }
    }
}

/// `GameSummaryRow`'s Next Up sheets — one row, one sheet at a time, so a
/// single `Identifiable` enum rather than several competing `Bool`/`item`
/// states.
private enum RowSheet: Identifiable {
    case picks(startFilteredToUnassigned: Bool = false)
    case submissionQueue
    case shareLastRound
    var id: String {
        switch self {
        case .picks: return "picks"
        case .submissionQueue: return "queue"
        case .shareLastRound: return "share"
        }
    }
}

/// A manager-facing status for the game's current round: how many of the
/// eligible players have submitted, and when it's due — or, once the
/// deadline's passed, who's still missing so the manager knows who to chase
/// (or enter for) before kickoff. This is purely informational — it never
/// blocks entry; see `RoundPhase`'s doc comment and `NextUpStep`.
struct ManagerRoundStatus {
    let label: String
    let detail: String
    let tint: Color
    /// Submitted/eligible for the current round's open submission window —
    /// nil once the deadline's passed or there's nothing to submit, so a
    /// finished round (or a "missing" nudge) doesn't show a stale bar.
    let submissionProgress: Double?
    /// Players still missing a pick, once the deadline's passed — nil before
    /// the deadline (already covered by the submitted/eligible label above)
    /// or once the round's closed/complete. `GameSummaryRow` surfaces this
    /// as a standing reminder chip that persists into live play, since the
    /// badge text itself moves on to match progress once kickoff happens.
    let missingCount: Int?

    static func make(for game: Game, data: LeagueData?) -> ManagerRoundStatus? {
        guard game.status != .complete else { return nil }

        switch RoundPhase.make(for: game, data: data) {
        case .complete:
            return nil
        case .addPlayers:
            return ManagerRoundStatus(label: "Not started", detail: "Needs players", tint: V2Theme.warning, submissionProgress: nil, missingCount: nil)
        case .openRound:
            return ManagerRoundStatus(label: "Not started", detail: "", tint: V2Theme.textSecondary, submissionProgress: nil, missingCount: nil)
        case .closed:
            let roundNumber = game.currentRound?.roundNumber ?? 0
            return ManagerRoundStatus(label: "Round \(roundNumber) closed", detail: "", tint: V2Theme.textTertiary, submissionProgress: nil, missingCount: nil)
        case .beforeDeadline:
            guard let round = game.currentRound else { return nil }
            let (eligible, submitted) = Self.submissionCounts(for: game, round: round)
            let allIn = eligible > 0 && submitted >= eligible
            let due = "Due " + Self.dateFormatter.string(from: round.deadline)
            return ManagerRoundStatus(
                label: "\(submitted)/\(eligible) submitted",
                detail: due,
                tint: allIn ? V2Theme.accent : V2Theme.warning,
                submissionProgress: eligible > 0 ? Double(submitted) / Double(eligible) : nil,
                missingCount: nil
            )
        case .beforeKickoff:
            // Discards RoundPhase's fixture-count payload — this status is
            // about submission counts (missing picks), not match progress;
            // that's what GameSummaryRow's own `.confirmEntries` branch
            // shows instead.
            guard let round = game.currentRound else { return nil }
            let (eligible, submitted) = Self.submissionCounts(for: game, round: round)
            let missing = eligible - submitted
            guard missing > 0 else {
                return ManagerRoundStatus(label: "All submitted", detail: "Kickoff pending", tint: V2Theme.accent, submissionProgress: nil, missingCount: nil)
            }
            // Deadline's passed, but nothing's locked — the manager can
            // still tap in a late/texted-in pick right up to kickoff. This
            // is a to-do count for them, not a gate.
            return ManagerRoundStatus(label: "Submissions closed", detail: "\(missing) missing", tint: V2Theme.warning, submissionProgress: nil, missingCount: missing)
        case .live(let finished, let total):
            var missing: Int?
            if let round = game.currentRound {
                let (eligible, submitted) = Self.submissionCounts(for: game, round: round)
                let count = eligible - submitted
                missing = count > 0 ? count : nil
            }
            return ManagerRoundStatus(label: "Live", detail: "\(finished)/\(total) matches in", tint: V2Theme.textSecondary, submissionProgress: nil, missingCount: missing)
        case .readyToProcess:
            let roundNumber = game.currentRound?.roundNumber ?? 0
            return ManagerRoundStatus(label: "Results due", detail: "Round \(roundNumber)", tint: V2Theme.danger, submissionProgress: nil, missingCount: nil)
        }
    }

    private static func submissionCounts(for game: Game, round: Round) -> (eligible: Int, submitted: Int) {
        switch game.mode {
        case .lms:
            return (game.activePlayers.count, round.picks.count)
        case .predictor:
            // Not `round.predictions.count` — that's one row per fixture
            // per player, not per player, so it overcounts by roughly the
            // fixture count (e.g. 14 players × 5 fixtures showed as
            // "70/14"). Count players with a complete slate instead.
            let eligible = game.players.count
            let submitted = game.players.filter { PredictorScoringService.slateComplete(for: $0, round: round) }.count
            return (eligible, submitted)
        case .killer:
            // Same overcounting risk as Predictor when a round has more than
            // one Manager Picked Game — count players, not prediction rows.
            let eligible = game.activePlayers.count
            let submitted = game.activePlayers.filter { KillerScoringService.slateComplete(for: $0, round: round, game: game) }.count
            return (eligible, submitted)
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Bundle.appLocale
        formatter.setLocalizedDateFormatFromTemplate("EEE d MMM HH:mm")
        return formatter
    }()
}
