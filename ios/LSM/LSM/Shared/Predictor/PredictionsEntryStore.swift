import Foundation
import SwiftData

/// Fixture/league data + tutorial-seeding logic for predictions entry, shared
/// by the classic `PredictionsEntryView` and the card-based
/// `PredictionsEntryViewV2` — kept in one place so both stay correct as the
/// UI is redesigned in parallel (mirrors `StandingsStore`'s split).
///
/// `fixtures` is computed once per `load()` rather than as a per-render
/// computed property: `LeagueData` is full-season/multi-league, and this
/// screen's core interaction (switching the selected player) re-evaluates
/// the view body on every tap, so a live filter-and-sort over `data.matches`
/// would redo that work on every player switch.
@Observable
final class PredictionsEntryStore {
    var data: LeagueData?
    private(set) var fixtures: [MatchDTO] = []
    var isLoading = false
    var errorMessage: String?

    func load(game: Game, round: Round) async {
        isLoading = true
        errorMessage = nil
        do {
            let loaded = try await LeagueData.load(for: game.leagues)
            data = loaded
            fixtures = Self.fixtures(from: loaded, round: round)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
        if game.isDemoData { seedTutorialPredictions(game: game, round: round) }
    }

    private static func fixtures(from data: LeagueData, round: Round) -> [MatchDTO] {
        let ids = Set(round.fixtureIds)
        return data.matches.filter { ids.contains($0.id) }.sorted(by: MatchDTO.byKickoffThenId)
    }

    /// Pre-fills all scripted predictions except Alex's fixture 8008, which
    /// the user enters themselves. Alex's other 3 fixtures are pre-filled too.
    private func seedTutorialPredictions(game: Game, round: Round) {
        let userFixtureId = TutorialDataGenerator.predictorFirstMatchId
        let context = game.modelContext
        for player in game.players {
            guard let script = TutorialDataGenerator.predictorScriptedPredictions[player.name] else { continue }
            for fixture in TutorialDataGenerator.predictorFixtures {
                // Leave Alex's first fixture blank for the user to enter
                if player.name == "Alex" && fixture.matchId == userFixtureId { continue }
                // Skip if already set
                let existing = PredictorScoringService.predictions(for: player, in: round)
                if existing.contains(where: { $0.fixtureId == fixture.matchId }) { continue }
                guard let pred = script[fixture.matchId], let context else { continue }
                PredictorScoringService.setPrediction(
                    player: player, round: round,
                    fixtureId: fixture.matchId, home: pred.home, away: pred.away,
                    context: context
                )
            }
        }
        try? context?.save()
    }
}
