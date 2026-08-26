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

    private var managerStatus: ManagerRoundStatus? { ManagerRoundStatus.make(for: game) }
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
        // screen.
        .task(id: roundContext.currentRound?.id) {
            guard let round = roundContext.currentRound, round.status != .closed, Date() >= round.deadline else { return }
            leagueData = try? await LeagueData.load(for: game.leagues)
        }
        .sheet(item: $sheet) { which in
            switch which {
            case .picks:
                if let round = roundContext.openRound { picksDestination(round: round) }
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
        case .enterPicks(let pwa):
            nextUpButton(title: pwa ? "Check Submission Queue" : "Enter Picks", icon: "square.and.pencil") {
                sheet = pwa ? .submissionQueue : .picks
            }
        case .confirmEntries(let pwa):
            nextUpButton(title: "Confirm Entries", icon: "checkmark.seal") {
                sheet = pwa ? .submissionQueue : .picks
            }
        case .matchesInProgress(let finished, let total):
            HStack(spacing: 8) {
                Image(systemName: "sportscourt")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(V2Theme.textSecondary)
                Text("Matches playing — \(finished) of \(total) in")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(V2Theme.textSecondary)
                Spacer()
                if roundContext.latestClosedRound != nil { shareButton }
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
    private func picksDestination(round: Round) -> some View {
        switch game.mode {
        case .lms: PicksEntryViewV2(game: game, round: round)
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
    case picks
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
/// eligible players have submitted, and when it's due — or, once submissions
/// close, whether the manager still needs to enter results.
struct ManagerRoundStatus {
    let label: String
    let detail: String
    let tint: Color
    /// Submitted/eligible for the current round's open submission window —
    /// nil once the window has closed (results/closed) or there's nothing
    /// to submit, so a finished round doesn't show a stale progress bar.
    let submissionProgress: Double?

    static func make(for game: Game) -> ManagerRoundStatus? {
        guard game.status != .complete else { return nil }
        guard let round = game.currentRound else {
            return ManagerRoundStatus(label: "Not started", detail: "", tint: V2Theme.textSecondary, submissionProgress: nil)
        }

        let eligible: Int
        let submitted: Int
        switch game.mode {
        case .lms:
            eligible = game.activePlayers.count
            submitted = round.picks.count
        case .predictor:
            // Not `round.predictions.count` — that's one row per fixture
            // per player, not per player, so it overcounts by roughly the
            // fixture count (e.g. 14 players × 5 fixtures showed as
            // "70/14"). Count players with a complete slate instead.
            eligible = game.players.count
            submitted = game.players.filter { PredictorScoringService.slateComplete(for: $0, round: round) }.count
        case .killer:
            // Same overcounting risk as Predictor when a round has more than
            // one Manager Picked Game — count players, not prediction rows.
            eligible = game.activePlayers.count
            submitted = game.activePlayers.filter { KillerScoringService.slateComplete(for: $0, round: round, game: game) }.count
        }

        let due = "Due " + Self.dateFormatter.string(from: round.deadline)
        switch round.status {
        case .open, .picks:
            let allIn = eligible > 0 && submitted >= eligible
            return ManagerRoundStatus(
                label: "\(submitted)/\(eligible) submitted",
                detail: due,
                tint: allIn ? V2Theme.accent : V2Theme.warning,
                submissionProgress: eligible > 0 ? Double(submitted) / Double(eligible) : nil
            )
        case .results:
            return ManagerRoundStatus(label: "Results due", detail: "Round \(round.roundNumber)", tint: V2Theme.danger, submissionProgress: nil)
        case .closed:
            return ManagerRoundStatus(label: "Round \(round.roundNumber) closed", detail: "", tint: V2Theme.textTertiary, submissionProgress: nil)
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Bundle.appLocale
        formatter.setLocalizedDateFormatFromTemplate("EEE d MMM HH:mm")
        return formatter
    }()
}
