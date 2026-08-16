import Testing
import Foundation
import SwiftData
@testable import LSM

/// Covers `GameSyncBuilder`'s identity-preservation contract — the whole
/// point of sync being a *move*, not a copy like `GameTransfer`: a
/// reconstructed game must keep the same `cloudGameTokenRaw` and the same
/// `Player.id`s the server already knows about (`game_enrollments.local_player_id`),
/// or existing PWA links/future pushes silently stop resolving to the right
/// game/player. Also covers the collision guard and the results-history
/// folding (LMS elimination, Killer cumulative stats) that "resume where I
/// left off" actually depends on.
struct GameSyncBuilderTests {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Game.self, Player.self, Round.self, Pick.self, Prediction.self,
            KillerPrediction.self, KillerPlayerState.self, RosterMember.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private let aliceLocalId = "11111111-1111-1111-1111-111111111111"
    private let bobLocalId = "22222222-2222-2222-2222-222222222222"

    private func decodeBundle(_ json: String) throws -> GameSyncBundle {
        try JSONDecoder().decode(GameSyncBundle.self, from: Data(json.utf8))
    }

    private var lmsConfigJSON: String {
        """
        {"leagueIdsRaw":["PL"],"season":"2025/26","allowRepeats":false,"anonymityModeRaw":"named",\
        "drawEliminates":true,"postponedEliminates":false,"modeRaw":"lms",\
        "predictorExactPoints":4,"predictorGDEnabled":true,"predictorGDPoints":3,\
        "predictorResultEnabled":true,"predictorResultPoints":2,"predictorJokerEnabled":false,\
        "killerBuildPhaseRounds":2,"killerMaxAdditionalLives":10,"killerMaxMPG":5}
        """
    }

    private func lmsBundleJSON(gameConfigJSON: String?, resultsJSON: String = "[]", approvedSubmissionsJSON: String = "[]") -> String {
        let configField = gameConfigJSON.map { "\"\($0.replacingOccurrences(of: "\"", with: "\\\""))\"" } ?? "null"
        return """
        {
          "syncable": \(gameConfigJSON != nil),
          "gameConfigJson": \(configField),
          "currentRound": {
            "mode": "lms", "roundNumber": 2, "deadline": null, "gameName": "Test League",
            "fixturesJson": "[{\\"fixtureId\\":101,\\"home\\":\\"A\\",\\"away\\":\\"B\\",\\"kickoff\\":\\"2026-08-20T00:00:00.000Z\\"}]",
            "jokerEnabled": false, "extraJson": null, "updatedAt": "2026-08-16T00:00:00.000Z"
          },
          "results": \(resultsJSON),
          "players": [
            {"token": "tok-alice", "playerName": "Alice", "localPlayerId": "\(aliceLocalId)", "eligibleTeamIdsJson": null, "managerSuffix": "a1"},
            {"token": "tok-bob", "playerName": "Bob", "localPlayerId": "\(bobLocalId)", "eligibleTeamIdsJson": null, "managerSuffix": "b2"}
          ],
          "approvedSubmissions": \(approvedSubmissionsJSON)
        }
        """
    }

    // MARK: - Identity preservation

    @Test func preservesCloudGameTokenAndPlayerIds() throws {
        let context = try makeContext()
        let bundle = try decodeBundle(lmsBundleJSON(gameConfigJSON: lmsConfigJSON))

        let game = try GameSyncBuilder.build(from: bundle, gameToken: "GAME-TOKEN-XYZ", into: context)

        #expect(game.cloudGameTokenRaw == "game-token-xyz")
        #expect(game.cloudRosterEnrolled == true)
        let alice = game.players.first { $0.name == "Alice" }
        let bob = game.players.first { $0.name == "Bob" }
        #expect(alice?.id.uuidString.lowercased() == aliceLocalId)
        #expect(bob?.id.uuidString.lowercased() == bobLocalId)
    }

    // MARK: - Collision guard

    @Test func refusesToSyncAGameAlreadyPresentLocally() throws {
        let context = try makeContext()
        let bundle = try decodeBundle(lmsBundleJSON(gameConfigJSON: lmsConfigJSON))

        _ = try GameSyncBuilder.build(from: bundle, gameToken: "dup-token", into: context)

        #expect(throws: GameSyncBuilder.BuildError.alreadySynced) {
            try GameSyncBuilder.build(from: bundle, gameToken: "dup-token", into: context)
        }
    }

    // MARK: - Not syncable / invalid config

    @Test func refusesToBuildWithoutGameConfig() throws {
        let context = try makeContext()
        let bundle = try decodeBundle(lmsBundleJSON(gameConfigJSON: nil))

        #expect(throws: GameSyncBuilder.BuildError.invalidConfig) {
            try GameSyncBuilder.build(from: bundle, gameToken: "no-config-token", into: context)
        }
    }

    // MARK: - LMS elimination folding

    @Test func foldsEliminationAcrossResultsHistory() throws {
        let context = try makeContext()
        // Round 1: both survive. Round 2 (most recent, though order shouldn't
        // matter — elimination is terminal): Bob eliminated, Alice survives.
        let results = """
        [
          {"roundNumber": 1, "mode": "lms", "createdAt": "2026-08-01T00:00:00.000Z",
           "resultsJson": "[{\\"playerId\\":\\"\(aliceLocalId)\\",\\"teamPicked\\":\\"Arsenal\\",\\"survived\\":true},{\\"playerId\\":\\"\(bobLocalId)\\",\\"teamPicked\\":\\"Chelsea\\",\\"survived\\":true}]"},
          {"roundNumber": 2, "mode": "lms", "createdAt": "2026-08-08T00:00:00.000Z",
           "resultsJson": "[{\\"playerId\\":\\"\(aliceLocalId)\\",\\"teamPicked\\":\\"Liverpool\\",\\"survived\\":true},{\\"playerId\\":\\"\(bobLocalId)\\",\\"teamPicked\\":\\"Everton\\",\\"survived\\":false}]"}
        ]
        """
        let bundle = try decodeBundle(lmsBundleJSON(gameConfigJSON: lmsConfigJSON, resultsJSON: results))

        let game = try GameSyncBuilder.build(from: bundle, gameToken: "elim-token", into: context)

        let alice = game.players.first { $0.name == "Alice" }
        let bob = game.players.first { $0.name == "Bob" }
        #expect(alice?.status == .active)
        #expect(bob?.status == .eliminated)
    }

    // MARK: - Approved submissions → current round Pick

    @Test func rebuildsCurrentRoundPicksFromApprovedSubmissions() throws {
        let context = try makeContext()
        let approved = """
        [{"token": "tok-alice", "payloadJson": "{\\"teamId\\":42,\\"fixtureId\\":101}"}]
        """
        let bundle = try decodeBundle(lmsBundleJSON(gameConfigJSON: lmsConfigJSON, approvedSubmissionsJSON: approved))

        let game = try GameSyncBuilder.build(from: bundle, gameToken: "picks-token", into: context)

        let round = game.rounds.first
        #expect(round?.roundNumber == 2)
        #expect(round?.picks.count == 1)
        #expect(round?.picks.first?.teamId == 42)
        #expect(round?.picks.first?.player?.name == "Alice")
        // Bob didn't submit — no Pick for him, but he's still a real Player.
        #expect(game.players.first { $0.name == "Bob" }?.id != nil)
    }

    // MARK: - Killer cumulative stats folding

    @Test func sumsKillerHitsAndCorrectPredictionsAcrossRounds() throws {
        let context = try makeContext()
        let killerConfig = lmsConfigJSON.replacingOccurrences(of: "\"modeRaw\":\"lms\"", with: "\"modeRaw\":\"killer\"")
        let results = """
        [
          {"roundNumber": 1, "mode": "killer", "createdAt": "2026-08-01T00:00:00.000Z",
           "resultsJson": "[{\\"playerId\\":\\"\(aliceLocalId)\\",\\"lives\\":2,\\"eliminated\\":false,\\"hitsLandedThisRound\\":1,\\"correctPredictionsThisRound\\":1}]"},
          {"roundNumber": 2, "mode": "killer", "createdAt": "2026-08-08T00:00:00.000Z",
           "resultsJson": "[{\\"playerId\\":\\"\(aliceLocalId)\\",\\"lives\\":1,\\"eliminated\\":false,\\"hitsLandedThisRound\\":2,\\"correctPredictionsThisRound\\":0}]"}
        ]
        """
        var json = lmsBundleJSON(gameConfigJSON: killerConfig, resultsJSON: results)
        json = json.replacingOccurrences(of: "\"mode\": \"lms\"", with: "\"mode\": \"killer\"")
        let bundle = try decodeBundle(json)

        let game = try GameSyncBuilder.build(from: bundle, gameToken: "killer-token", into: context)

        let alice = game.players.first { $0.name == "Alice" }
        #expect(alice?.killerState?.lives == 1) // latest round's value, not summed
        #expect(alice?.killerState?.successfulHitsLanded == 3) // 1 + 2, summed
        #expect(alice?.killerState?.correctPredictions == 1) // 1 + 0, summed
    }

    // MARK: - Predictor carried-over points (no fake Round/Prediction)

    @Test func carriesOverLatestCumulativePredictorPointsWithoutFakingHistory() throws {
        let context = try makeContext()
        let predictorConfig = lmsConfigJSON.replacingOccurrences(of: "\"modeRaw\":\"lms\"", with: "\"modeRaw\":\"predictor\"")
        let results = """
        [
          {"roundNumber": 1, "mode": "predictor", "createdAt": "2026-08-01T00:00:00.000Z",
           "resultsJson": "[{\\"playerId\\":\\"\(aliceLocalId)\\",\\"pointsThisRound\\":10,\\"cumulativePoints\\":10,\\"position\\":1}]"},
          {"roundNumber": 2, "mode": "predictor", "createdAt": "2026-08-08T00:00:00.000Z",
           "resultsJson": "[{\\"playerId\\":\\"\(aliceLocalId)\\",\\"pointsThisRound\\":22,\\"cumulativePoints\\":32,\\"position\\":1}]"}
        ]
        """
        var json = lmsBundleJSON(gameConfigJSON: predictorConfig, resultsJSON: results)
        json = json.replacingOccurrences(of: "\"mode\": \"lms\"", with: "\"mode\": \"predictor\"")
        let bundle = try decodeBundle(json)

        let game = try GameSyncBuilder.build(from: bundle, gameToken: "predictor-token", into: context)

        let alice = game.players.first { $0.name == "Alice" }
        #expect(alice?.carriedOverPoints == 32) // latest cumulativePoints, not summed across rounds
        // No fake Round was created to hold this — only the real current round exists.
        #expect(game.rounds.count == 1)
        #expect(game.rounds.first?.predictions.isEmpty == true)
        // Standings reflect the carry-over via the live sum, not a fabricated Prediction.
        let standings = PredictorStandings.rows(for: game)
        #expect(standings.first { $0.player.name == "Alice" }?.points == 32)
    }
}
