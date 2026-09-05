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
                Text(detailLine)
                    .font(.caption)
                    .foregroundStyle(V2Theme.textSecondary)
                resultsLine
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
        case .processResults(let total) where total > 0:
            // Every fixture's finished/postponed but the manager hasn't
            // tapped Process Results yet — without this the line would
            // just disappear the moment the last match ends, which is
            // exactly the gap Andrew hit on a Killer game whose fixtures
            // had already completed.
            resultsRow(finished: total, total: total, label: "Complete")
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
                MicroLabel(verbatim: V2Theme.Mode.displayName(for: game.mode), tint: modeColor)
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

    /// One compact line — round/matchday plus the single most relevant stat
    /// per mode — replacing the old 2x2 stat grid so this card fits on one
    /// glance-height line, same compression `GameSummaryRow.detailLine`
    /// already uses for its own row. LMS/Killer show the full "X of Y"
    /// ratio (not just remaining count) per Andrew's ask; Predictor keeps
    /// the leader, dropping "last week" to stay on one line.
    private var detailLine: String {
        let roundLabel = game.mode == .predictor ? "Matchday" : "Round"
        let roundPart = round.map { "\(roundLabel) \($0.roundNumber) · " } ?? ""
        switch game.mode {
        case .lms, .killer:
            return "\(roundPart)\(game.activePlayers.count) of \(game.players.count) players left"
        case .predictor:
            if let leader = PredictorStandings.leaderName(for: game) {
                return "\(roundPart)Leading: \(leader)"
            }
            return "\(roundPart)\(game.players.count) players"
        }
    }
}
