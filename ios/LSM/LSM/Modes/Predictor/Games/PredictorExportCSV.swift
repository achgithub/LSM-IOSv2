import Foundation

/// CSV export for a Predictor game's full history — mirrors LMS's
/// `GameExportCSV`. Two files: game-level settings, and one row per
/// round × player × fixture (Predictor's natural unit — a round has several
/// fixtures, unlike LMS's one-pick-per-round).
enum PredictorExportCSV {
    static func metadataCSV(for game: Game) -> String {
        var lines: [String] = []
        func row(_ key: String, _ value: String) { lines.append([key, value].map(escape).joined(separator: ",")) }

        row("Game Name", game.name)
        row("Season", game.season)
        row("Leagues", game.leagues.map(\.name).joined(separator: "; "))
        row("Exact Score Points", String(game.predictorExactPoints))
        row("Goal Difference Enabled", game.predictorGDEnabled ? "true" : "false")
        row("Goal Difference Points", String(game.predictorGDPoints))
        row("Correct Result Enabled", game.predictorResultEnabled ? "true" : "false")
        row("Correct Result Points", String(game.predictorResultPoints))
        row("Joker Enabled", game.predictorJokerEnabled ? "true" : "false")
        row("Status", game.status.label)
        let winners = game.players.filter { $0.status == .winner }
        if !winners.isEmpty {
            row("Winner", winners.map(\.name).joined(separator: ", "))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// One row per round × player × fixture: their prediction for that
    /// fixture (if any), the actual score once the round closes, and points
    /// awarded. Player status is the current/final status, repeated across
    /// every row — a snapshot, not a status history, same as LMS's picksCSV.
    static func predictionsCSV(for game: Game, data: LeagueData) -> String {
        let header = ["Round Number", "Player", "Player Status", "Fixture", "Match Time", "Predicted Score", "Actual Score", "Points Awarded", "Joker"]
        var lines = [header.map(escape).joined(separator: ",")]

        let matchesById = Dictionary(data.matches.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let rounds = game.rounds.sorted { $0.roundNumber < $1.roundNumber }
        let players = game.players.sorted { $0.entryNumber < $1.entryNumber }

        for round in rounds {
            let fixtureIds = round.fixtureIds
            for player in players {
                let predictionsByFixture = Dictionary(
                    round.predictions.filter { $0.player?.id == player.id }.map { ($0.fixtureId, $0) },
                    uniquingKeysWith: { first, _ in first }
                )
                for fixtureId in fixtureIds {
                    let fixture = matchesById[fixtureId]
                    let prediction = predictionsByFixture[fixtureId]

                    let fixtureLabel = fixture.map { "\(teamName(for: $0.homeTeamId, data: data)) v \(teamName(for: $0.awayTeamId, data: data))" } ?? ""
                    let matchTime = fixture
                        .flatMap { FixtureFormat.kickoffDate($0.kickoff) }
                        .map(Self.timeFormatter.string(from:))

                    let predictedScore = prediction.map { "\($0.predictedHome)-\($0.predictedAway)" } ?? ""
                    let actualScore: String
                    if let prediction, let actualHome = prediction.actualHome, let actualAway = prediction.actualAway {
                        actualScore = "\(actualHome)-\(actualAway)"
                    } else if round.status == .closed, prediction != nil {
                        actualScore = "Voided"
                    } else {
                        actualScore = ""
                    }
                    let pointsAwarded = prediction?.pointsAwarded.map(String.init) ?? ""
                    let joker = (prediction?.isJoker == true) ? "Y" : ""

                    let fields = [
                        String(round.roundNumber),
                        player.name,
                        player.status.label,
                        fixtureLabel,
                        matchTime ?? "",
                        predictedScore,
                        actualScore,
                        pointsAwarded,
                        joker,
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
