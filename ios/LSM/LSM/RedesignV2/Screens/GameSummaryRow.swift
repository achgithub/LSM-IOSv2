import SwiftUI

/// One game's card row — extracted from `GamesPortalViewV2` so it can be
/// reused by Home's Favourites section as well as the Games screen's
/// per-mode sections. Mode-agnostic: computes its own manager-facing status
/// and standing preview from the shared scoring services, so it can't drift
/// from the real share-card numbers.
struct GameSummaryRow: View {
    let game: Game
    /// Resumes this game's Guided Setup wizard at its current phase. Wired
    /// up by both the Games portal and Home's Favourites card; default
    /// no-op only as a safety net for any future caller that doesn't need it.
    var onResume: () -> Void = {}

    private var managerStatus: ManagerRoundStatus? { ManagerRoundStatus.make(for: game) }
    private var modeColor: Color { V2Theme.Mode.color(for: game.mode) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: V2Theme.Mode.icon(for: game.mode))
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(modeColor)
                    .frame(width: 42, height: 42)
                    .background(modeColor.opacity(0.15), in: RoundedRectangle(cornerRadius: V2Theme.Radius.pill, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    MicroLabel(text: V2Theme.Mode.displayName(for: game.mode), tint: modeColor)
                    Text(game.name)
                        .font(.system(.headline, design: V2Theme.Mode.fontDesign(for: game.mode)).weight(.bold))
                        .foregroundStyle(V2Theme.textPrimary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Button {
                    onResume()
                } label: {
                    Image(systemName: "wand.and.stars")
                        .font(.body)
                        .foregroundStyle(V2Theme.accent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Resume Guided Setup")
                // Fixed extra gap (beyond the row's base 8pt spacing), not
                // another flexible Spacer — this needs to stay a constant
                // distance from the favourite/chevron pair, not compete with
                // the leading Spacer for the row's slack space. A mis-tap
                // here launches a full-screen wizard, not a toggle.
                Spacer().frame(width: 16)
                Button {
                    game.isFavourite.toggle()
                } label: {
                    Image(systemName: game.isFavourite ? "star.fill" : "star")
                        .font(.body)
                        .foregroundStyle(game.isFavourite ? V2Theme.warning : V2Theme.textTertiary)
                }
                .buttonStyle(.plain)
                NavigationLink {
                    destination
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(V2Theme.textSecondary)
                        .frame(width: 28, height: 28)
                }
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
        }
        .padding(14)
        .v2FloatingCard()
    }

    @ViewBuilder
    private var destination: some View {
        switch game.mode {
        case .lms: GameDetailViewV2(game: game)
        case .predictor: PredictorGameDetailViewV2(game: game)
        case .killer: KillerGameDetailViewV2(game: game)
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
