import Foundation

enum KillerCardType: Equatable {
    case fixtures
    /// Kill Phase only — the numbered opponent key the texted shorthand's
    /// Hit-target number refers to.
    case playerKey
    case weeklyResults
    case standings
    case winner
}

extension KillerCardType {
    var sectionLabel: String {
        switch self {
        case .fixtures:      return AppString("MANAGER PICKED GAMES")
        case .playerKey:     return AppString("PLAYER KEY")
        case .weeklyResults: return AppString("WEEKLY RESULTS")
        case .standings:     return AppString("ACCURACY TABLE")
        case .winner:        return AppString("FINAL RESULT")
        }
    }
}

/// A Manager Picked Game, numbered in round order — the number the texted
/// shorthand's fixture digit refers to (e.g. the "1" in "1H2").
struct KillerNumberedFixture: Identifiable {
    let id: Int
    let number: Int
    let homeName: String
    let awayName: String
    let kickoff: Date?
}

/// One opponent in the numbered player key — the number the texted
/// shorthand's Hit-target digit refers to (e.g. the "2" in "1H2"). Numbered
/// alphabetically over active players, recomputed fresh each round rather
/// than stored (same pattern as fixture numbering).
struct KillerPlayerKeyEntry: Identifiable {
    let id: UUID
    let number: Int
    let playerName: String
}

struct KillerWeekResult: Identifiable {
    let id: UUID
    let playerName: String
    let lives: Int
    let hitsReceived: Int
    let eliminatedThisRound: Bool
}

struct KillerStandingEntry: Identifiable {
    let id: UUID
    let playerName: String
    let lives: Int
    let correctPredictions: Int
    let successfulHitsLanded: Int
    let isEliminated: Bool
}

struct KillerWinnerEntry: Identifiable {
    let id: UUID
    let playerName: String
}

/// Flattened, render-ready snapshot for a Killer share card. A pure value
/// type with no SwiftData model references so it renders safely under
/// ImageRenderer. Computed fresh from live models every call, same as
/// `PredictorCardData`/`SummaryData` — no stored per-round snapshot needed.
struct KillerCardData {
    let type: KillerCardType
    let gameName: String
    let appName: String
    let leagueName: String
    let roundNumber: Int
    let entrantCount: Int
    let timestampLabel: String
    let fixtures: [KillerNumberedFixture]
    let playerKey: [KillerPlayerKeyEntry]
    let weeklyResults: [KillerWeekResult]
    let standings: [KillerStandingEntry]
    let winners: [KillerWinnerEntry]

    static func make(
        type: KillerCardType,
        game: Game,
        round: Round,
        teamsById: [Int: TeamDTO],
        roundMatches: [MatchDTO]
    ) -> KillerCardData {
        KillerCardData(
            type: type,
            gameName: game.name,
            appName: "Killer",
            leagueName: game.leagueLabel,
            roundNumber: round.roundNumber,
            entrantCount: game.players.count,
            timestampLabel: makeTimestamp(type: type, round: round),
            fixtures: makeFixtures(round: round, matches: roundMatches, teamsById: teamsById),
            playerKey: makePlayerKey(game: game),
            weeklyResults: makeWeeklyResults(game: game, round: round),
            standings: makeStandings(game: game),
            winners: makeWinners(game: game)
        )
    }

    // MARK: - Builders

    private static func teamName(_ id: Int, _ teamsById: [Int: TeamDTO]) -> String {
        teamsById[id]?.shortName ?? teamsById[id]?.name ?? "Team \(id)"
    }

    /// Numbered in `round.fixtureIds` order (the manager's MPG order at
    /// round-open), not re-sorted by kickoff — this order is what both the
    /// fixtures card and the scratchpad shorthand key off.
    private static func makeFixtures(
        round: Round, matches: [MatchDTO], teamsById: [Int: TeamDTO]
    ) -> [KillerNumberedFixture] {
        let byId = Dictionary(uniqueKeysWithValues: matches.map { ($0.id, $0) })
        return round.fixtureIds.enumerated().compactMap { index, fixtureId in
            guard let match = byId[fixtureId] else { return nil }
            return KillerNumberedFixture(
                id: fixtureId,
                number: index + 1,
                homeName: teamName(match.homeTeamId, teamsById),
                awayName: teamName(match.awayTeamId, teamsById),
                kickoff: FixtureFormat.kickoffDate(match.kickoff)
            )
        }
    }

    private static func makePlayerKey(game: Game) -> [KillerPlayerKeyEntry] {
        game.activePlayers
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .enumerated()
            .map { index, player in KillerPlayerKeyEntry(id: player.id, number: index + 1, playerName: player.name) }
    }

    private static func makeTimestamp(type: KillerCardType, round: Round) -> String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE d MMM HH:mm")
        switch type {
        case .fixtures, .playerKey:
            return AppString("Deadline · \(formatter.string(from: round.deadline))")
        case .weeklyResults, .standings, .winner:
            return AppString("Round \(round.roundNumber)")
        }
    }

    /// Lives, Hits received, and eliminated-this-round are all derived — no
    /// stored per-round snapshot needed (see the Killer implementation plan's
    /// "data sufficiency" note): lives is the current post-close value; Hits
    /// received is a straight count of this round's landed Hits against the
    /// player; eliminated-this-round reconstructs the pre-damage life total
    /// (`lives + damageTakenThisRound`) to distinguish a fresh elimination
    /// from one that already happened in an earlier round.
    private static func makeWeeklyResults(game: Game, round: Round) -> [KillerWeekResult] {
        game.players
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map { player in
                let hitsReceived = round.killerPredictions.filter {
                    $0.hitTargetPlayerId == player.id && $0.hitLanded == true
                }.count
                let lives = max(0, player.killerState?.lives ?? 0)
                let livesBeforeThisRound = (player.killerState?.lives ?? 0) + hitsReceived
                let eliminatedThisRound = livesBeforeThisRound > 0 && (player.killerState?.lives ?? 0) <= 0
                return KillerWeekResult(
                    id: player.id, playerName: player.name, lives: lives,
                    hitsReceived: hitsReceived, eliminatedThisRound: eliminatedThisRound
                )
            }
    }

    private static func makeStandings(game: Game) -> [KillerStandingEntry] {
        game.players
            .sorted { a, b in
                let livesA = a.killerState?.lives ?? 0
                let livesB = b.killerState?.lives ?? 0
                if livesA != livesB { return livesA > livesB }
                let correctA = a.killerState?.correctPredictions ?? 0
                let correctB = b.killerState?.correctPredictions ?? 0
                if correctA != correctB { return correctA > correctB }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
            .map { player in
                KillerStandingEntry(
                    id: player.id,
                    playerName: player.name,
                    lives: max(0, player.killerState?.lives ?? 0),
                    correctPredictions: player.killerState?.correctPredictions ?? 0,
                    successfulHitsLanded: player.killerState?.successfulHitsLanded ?? 0,
                    isEliminated: player.status == .eliminated
                )
            }
    }

    private static func makeWinners(game: Game) -> [KillerWinnerEntry] {
        game.players
            .filter { $0.status == .winner }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map { KillerWinnerEntry(id: $0.id, playerName: $0.name) }
    }
}
