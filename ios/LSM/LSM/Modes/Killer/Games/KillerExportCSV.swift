import Foundation

/// CSV export for a Killer game's full history — mirrors LMS's
/// `GameExportCSV`. Two files: game-level settings, and one row per
/// round × player × fixture, from `round.killerPredictions`.
enum KillerExportCSV {
    static func metadataCSV(for game: Game) -> String {
        var lines: [String] = []
        func row(_ key: String, _ value: String) { lines.append([key, value].map(escape).joined(separator: ",")) }

        row("Game Name", game.name)
        row("Season", game.season)
        row("Leagues", game.leagues.map(\.name).joined(separator: "; "))
        row("Build Phase Rounds", String(game.killerBuildPhaseRounds))
        row("Max Additional Lives", String(game.killerMaxAdditionalLives))
        row("Max Manager Picked Games", String(game.killerMaxMPG))
        row("Status", game.status.label)
        let winners = game.players.filter { $0.status == .winner }
        if !winners.isEmpty {
            row("Winner", winners.map(\.name).joined(separator: ", "))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// One row per round × player × fixture: their prediction for that
    /// fixture, the actual outcome once the round closes, whether it was
    /// correct, and (Kill Phase) their hit target and whether it landed.
    /// Lives is a current/final snapshot, not a per-round history — no
    /// per-round lives-delta is stored anywhere to reconstruct history from,
    /// same limitation LMS's own `picksCSV` already accepts for player status.
    static func predictionsCSV(for game: Game, data: LeagueData) -> String {
        let header = ["Round Number", "Phase", "Player", "Player Status", "Lives", "Fixture", "Match Time", "Predicted Outcome", "Actual Outcome", "Correct", "Hit Target", "Hit Landed"]
        var lines = [header.map(escape).joined(separator: ",")]

        let matchesById = Dictionary(data.matches.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let playersById = Dictionary(game.players.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let rounds = game.rounds.sorted { $0.roundNumber < $1.roundNumber }
        let players = game.players.sorted { $0.entryNumber < $1.entryNumber }

        for round in rounds {
            let phase = KillerScoringService.phase(for: round, game: game)
            let fixtureIds = round.fixtureIds
            for player in players {
                let predictionsByFixture = Dictionary(
                    round.killerPredictions.filter { $0.player?.id == player.id }.map { ($0.fixtureId, $0) },
                    uniquingKeysWith: { first, _ in first }
                )
                for fixtureId in fixtureIds {
                    let fixture = matchesById[fixtureId]
                    let prediction = predictionsByFixture[fixtureId]

                    let fixtureLabel = fixture.map { "\(teamName(for: $0.homeTeamId, data: data)) v \(teamName(for: $0.awayTeamId, data: data))" } ?? ""
                    let matchTime = fixture
                        .flatMap { FixtureFormat.kickoffDate($0.kickoff) }
                        .map(Self.timeFormatter.string(from:))

                    let predictedOutcome = prediction?.predictedOutcome.label ?? ""
                    let actualOutcome: String
                    if let outcome = prediction?.actualOutcome {
                        actualOutcome = outcome.label
                    } else if round.status == .closed, prediction != nil {
                        actualOutcome = "Voided"
                    } else {
                        actualOutcome = ""
                    }
                    let correct: String
                    if let wasCorrect = prediction?.wasCorrect {
                        correct = wasCorrect ? "Yes" : "No"
                    } else {
                        correct = ""
                    }
                    let hitTarget = prediction?.hitTargetPlayerId.flatMap { playersById[$0]?.name } ?? ""
                    let hitLanded = (prediction?.hitLanded == true) ? "Yes" : ""

                    let fields = [
                        String(round.roundNumber),
                        phase == .build ? "Build" : "Kill",
                        player.name,
                        player.status.label,
                        String(max(0, player.killerState?.lives ?? 0)),
                        fixtureLabel,
                        matchTime ?? "",
                        predictedOutcome,
                        actualOutcome,
                        correct,
                        hitTarget,
                        hitLanded,
                    ]
                    lines.append(fields.map(escape).joined(separator: ","))
                }
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func teamName(for teamId: Int, data: LeagueData) -> String {
        guard let team = data.teamsById[teamId] else { return "Team \(teamId)" }
        return team.shortName ?? team.name
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.timeZone = .current
        return formatter
    }()

    nonisolated private static func escape(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\n") else { return field }
        return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
