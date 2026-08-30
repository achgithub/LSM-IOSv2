import SwiftUI

/// Home's Favourites card — informational only, unlike `GameSummaryRow`
/// (Games portal's own list row): no resume-wizard shortcut, no inline
/// favourite toggle, nothing that mutates state. It's a glance at "where's
/// this game right now," not a set of controls.
///
/// Tapping it doesn't push straight to game detail either — it jumps into
/// the Games portal already scrolled to this game's row (see
/// `GamesPortalViewV2.focusGameID`), so Favourites stays a status widget and
/// Portal stays the one place a game is actually acted on.
struct FavouriteGameCard: View {
    let game: Game

    @State private var leagueData: LeagueData?

    private var modeColor: Color { V2Theme.Mode.color(for: game.mode) }
    private var round: Round? { game.currentRound }
    // `pwaEnabled` only changes NextUpStep's wording for `.enterPicks` —
    // this card never reaches that case (it only reads the fixture count
    // out of `.confirmEntries`/`.matchesInProgress`, both unaffected by
    // this flag), so a real Entitlements/AppStorage lookup isn't needed
    // just to feed a value that wouldn't change what's shown.
    private var nextUp: NextUpStep { NextUpStep.make(for: game, data: leagueData, pwaEnabled: false) }

    var body: some View {
        NavigationLink {
            GamesPortalViewV2(focusGameID: game.id)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                header
                resultsLine
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 10) {
                    ForEach(stats, id: \.label) { stat in
                        statView(stat)
                    }
                }
            }
            .padding(14)
            .v2FloatingCard()
        }
        .buttonStyle(.plain)
        // Cache-only (never fetches — `SyncScheduler`, from Home's own
        // `.onAppear`/live-poll loop, is what actually keeps this cache
        // fresh; see docs/sync-refresh-policy.md), re-read every 60s while
        // there's a fixture count worth watching (pre-kickoff through
        // live), same pattern as `GameSummaryRow`.
        .task(id: round?.id) {
            guard let round, round.status != .closed, Date() >= round.deadline else { return }
            while !Task.isCancelled {
                leagueData = try? await LeagueData.load(for: game.leagues)
                switch NextUpStep.make(for: game, data: leagueData, pwaEnabled: false) {
                case .confirmEntries, .matchesInProgress:
                    try? await Task.sleep(for: .seconds(60))
                case .addPlayers, .openRound, .enterPicks, .processResults, .none:
                    return
                }
            }
        }
    }

    /// The one piece of "where's this game right now" `stats` below can't
    /// show — round/roster/attrition are static once the round opens, but
    /// fixture progress is exactly the thing that changes minute-to-minute
    /// once a round's locked, and this card exists to be glanced at without
    /// opening the Games portal. Same "X of Y in" language as
    /// `GameSummaryRow`, shown ahead of kickoff too (see
    /// `RoundPhase.beforeKickoff`).
    @ViewBuilder
    private var resultsLine: some View {
        switch nextUp {
        case .confirmEntries(_, let finished, let total) where total > 0:
            resultsRow(finished: finished, total: total, label: "Kicks off soon")
        case .matchesInProgress(let finished, let total):
            resultsRow(finished: finished, total: total, label: "Matches playing")
        default:
            EmptyView()
        }
    }

    private func resultsRow(finished: Int, total: Int, label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "sportscourt")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(V2Theme.textSecondary)
            Text("\(label) — \(finished) of \(total) in")
                .font(.caption.weight(.semibold))
                .foregroundStyle(V2Theme.textSecondary)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: V2Theme.Mode.icon(for: game.mode))
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(modeColor)
                .frame(width: 34, height: 34)
                .background(modeColor.opacity(0.15), in: RoundedRectangle(cornerRadius: V2Theme.Radius.pill, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                MicroLabel(text: V2Theme.Mode.displayName(for: game.mode), tint: modeColor)
                Text(game.name)
                    .font(.system(.headline, design: V2Theme.Mode.fontDesign(for: game.mode)).weight(.bold))
                    .foregroundStyle(V2Theme.textPrimary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(V2Theme.textTertiary)
        }
    }

    private func statView(_ stat: Stat) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(stat.value)
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(V2Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            MicroLabel(text: stat.label)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private struct Stat {
        let label: String
        let value: String
    }

    /// Round + starting roster size are the same shape for every mode;
    /// what fills the other two slots is mode-specific — LMS/Killer care
    /// about attrition (who's still in), Predictor cares about form (who
    /// won last time, who's leading overall).
    private var stats: [Stat] {
        let roundLabel = game.mode == .predictor ? "MATCHDAY" : "ROUND"
        let roundValue = round.map { "\($0.roundNumber)" } ?? "—"
        let startedStat = Stat(label: "STARTED WITH", value: "\(game.players.count)")

        switch game.mode {
        case .lms, .killer:
            return [
                Stat(label: roundLabel, value: roundValue),
                startedStat,
                Stat(label: "PLAYERS LEFT", value: "\(game.activePlayers.count)"),
            ]
        case .predictor:
            let lastWeek = latestClosedRound.flatMap { PredictorStandings.roundWinnerName(for: game, in: $0) } ?? "—"
            let leader = PredictorStandings.leaderName(for: game) ?? "—"
            return [
                Stat(label: roundLabel, value: roundValue),
                startedStat,
                Stat(label: "LAST WEEK", value: lastWeek),
                Stat(label: "TOP OF LEAGUE", value: leader),
            ]
        }
    }

    private var latestClosedRound: Round? {
        game.rounds.filter { $0.status == .closed }.max(by: { $0.roundNumber < $1.roundNumber })
    }
}
