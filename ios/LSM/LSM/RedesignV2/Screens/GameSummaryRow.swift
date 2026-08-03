import SwiftUI

/// One game's card row — extracted from `GamesPortalViewV2` so it can be
/// reused by Home's Favourites section as well as the Games screen's
/// per-mode sections. Mode-agnostic: computes its own manager-facing status
/// and standing preview from the shared scoring services, so it can't drift
/// from the real share-card numbers.
struct GameSummaryRow: View {
    let game: Game
    @State private var expanded = false

    private var managerStatus: ManagerRoundStatus? { ManagerRoundStatus.make(for: game) }
    private var collapsedLimit: Int { 2 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(game.name)
                    .font(V2Theme.Typography.rowTitle)
                    .foregroundStyle(V2Theme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 8)
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
            } else {
                V2StatusBadge(label: "Complete", tint: V2Theme.textSecondary)
            }

            let entries = standingEntries
            if !entries.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(expanded ? entries : Array(entries.prefix(collapsedLimit))) { entry in
                        HStack(spacing: 6) {
                            Image(systemName: entry.icon)
                                .font(.system(size: 11))
                                .foregroundStyle(entry.iconTint)
                            Text(entry.text)
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(entry.isMuted ? V2Theme.textTertiary : V2Theme.textPrimary)
                                .strikethrough(entry.isMuted)
                            if let hasSubmitted = entry.hasSubmitted {
                                Image(systemName: hasSubmitted ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 11))
                                    .foregroundStyle(hasSubmitted ? V2Theme.accent : V2Theme.textTertiary)
                            }
                            if !entry.trailing.isEmpty {
                                Spacer(minLength: 4)
                                Text(entry.trailing)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(entry.isMuted ? V2Theme.textTertiary : V2Theme.accent)
                            }
                        }
                    }
                }
                if entries.count > collapsedLimit {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
                    } label: {
                        Text(expanded ? "Show less" : "+\(entries.count - collapsedLimit) more")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(V2Theme.accent)
                    }
                }
            }
        }
        .padding(12)
        .background(V2Theme.pillBackground, in: RoundedRectangle(cornerRadius: V2Theme.Radius.row, style: .continuous))
    }

    @ViewBuilder
    private var destination: some View {
        switch game.mode {
        case .lms: GameDetailView(game: game)
        case .predictor: PredictorGameDetailViewV2(game: game)
        case .killer: KillerGameDetailViewV2(game: game)
        }
    }

    /// Mode-appropriate standing, one entry per line — full list available
    /// via the row's own "+more" expand, no separate navigation needed.
    private var standingEntries: [StandingEntry] {
        switch game.mode {
        case .lms:
            let round = game.currentRound
            let submittedIds = Set((round?.picks ?? []).compactMap { $0.player?.id })
            let sorted = game.players.sorted { lhs, rhs in
                if (lhs.status == .eliminated) != (rhs.status == .eliminated) { return lhs.status != .eliminated }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            return sorted.map { player in
                let out = player.status == .eliminated
                return StandingEntry(
                    id: player.id.uuidString,
                    icon: out ? "xmark" : "flame.fill",
                    iconTint: out ? V2Theme.danger : V2Theme.accent,
                    text: player.name,
                    trailing: out ? "OUT" : "",
                    isMuted: out,
                    hasSubmitted: (out || round == nil) ? nil : submittedIds.contains(player.id)
                )
            }
        case .predictor:
            let round = game.currentRound
            let rows = PredictorStandings.rows(for: game)
            return rows.map { row in
                StandingEntry(
                    id: row.id.uuidString,
                    icon: "number",
                    iconTint: V2Theme.accent,
                    text: "\(row.position). \(row.player.name)",
                    trailing: "\(row.points)pts",
                    isMuted: false,
                    // A full slate, not just "has any prediction row" — a
                    // player with 1 of 10 fixtures done isn't submitted yet.
                    hasSubmitted: round.map { PredictorScoringService.slateComplete(for: row.player, round: $0) }
                )
            }
        case .killer:
            let round = game.currentRound
            let standings = KillerCardData.makeStandings(game: game)
            return standings.map { entry in
                let hasSubmitted: Bool? = (entry.isEliminated || round == nil) ? nil : round.flatMap { r in
                    game.players.first(where: { $0.id == entry.id }).map {
                        KillerScoringService.slateComplete(for: $0, round: r, game: game)
                    }
                }
                return StandingEntry(
                    id: entry.id.uuidString,
                    icon: entry.isEliminated ? "xmark" : "heart.fill",
                    iconTint: entry.isEliminated ? V2Theme.danger : V2Theme.accent,
                    text: entry.playerName,
                    trailing: entry.isEliminated ? "OUT" : "\(entry.lives)",
                    isMuted: entry.isEliminated,
                    hasSubmitted: hasSubmitted
                )
            }
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

    static func make(for game: Game) -> ManagerRoundStatus? {
        guard game.status != .complete else { return nil }
        guard let round = game.currentRound else {
            return ManagerRoundStatus(label: "Not started", detail: "", tint: V2Theme.textSecondary)
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
                tint: allIn ? V2Theme.accent : V2Theme.warning
            )
        case .results:
            return ManagerRoundStatus(label: "Results due", detail: "Round \(round.roundNumber)", tint: V2Theme.danger)
        case .closed:
            return ManagerRoundStatus(label: "Round \(round.roundNumber) closed", detail: "", tint: V2Theme.textTertiary)
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Bundle.appLocale
        formatter.setLocalizedDateFormatFromTemplate("EEE d MMM HH:mm")
        return formatter
    }()
}

/// One line in a game's standing preview — icon + name (+ optional trailing
/// value), styled per the reference's alive/out treatment.
struct StandingEntry: Identifiable {
    let id: String
    let icon: String
    let iconTint: Color
    let text: String
    let trailing: String
    let isMuted: Bool
    /// Whether this (still-in) player has submitted for the current round —
    /// nil when not applicable (eliminated, or no open round). Read from the
    /// round's own Pick/Prediction/KillerPrediction records, not mocked.
    let hasSubmitted: Bool?
}
