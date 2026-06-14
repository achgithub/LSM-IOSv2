//
//  LMSTests.swift
//  LMSTests
//

import Testing
import Foundation
@testable import LMS

/// Foundation tests for the models/enums. The deterministic rules engine
/// (auto-assign, eliminations, the five tie rules) gets its own dedicated tests
/// when it's ported in Phase 3 — these just lock in the building blocks.
struct ModelTests {

    @Test func newGameStartsInSetupWithNoPlayers() {
        let game = Game(name: "Office LMS", season: "2025/26", allowRepeats: false, tieRule: .rolloverRound)
        #expect(game.status == .setup)
        #expect(game.players.isEmpty)
        #expect(game.currentRound == nil)
        #expect(game.tieRule == .rolloverRound)
    }

    @Test func gameStatusWrapperRoundTrips() {
        let game = Game(name: "G", season: "2025/26", allowRepeats: true, tieRule: .split)
        game.status = .active
        #expect(game.statusRaw == "active")
        #expect(game.status == .active)
    }

    @Test func newPlayerIsActive() {
        let player = Player(name: "Dave")
        #expect(player.status == .active)
        #expect(player.roundsSurvived == 0)
        #expect(player.weakPicks == 0)
    }

    @Test func pickResultStartsNil() {
        let pick = Pick(teamId: 57)
        #expect(pick.result == nil)
        pick.result = .win
        #expect(pick.resultRaw == "win")
        #expect(pick.result == .win)
    }
}

struct TieRuleTests {

    @Test func allFiveRulesHaveLabelAndDetail() {
        #expect(TieRule.allCases.count == 5)
        for rule in TieRule.allCases {
            #expect(!rule.label.isEmpty)
            #expect(!rule.detail.isEmpty)
        }
    }

    @Test(arguments: [
        ("split", TieRule.split),
        ("rollover_round", TieRule.rolloverRound),
        ("full_reset", TieRule.fullReset),
        ("sudden_death", TieRule.suddenDeath),
        ("longevity", TieRule.longevity),
    ])
    func rawValuesMatchSpec(raw: String, rule: TieRule) {
        #expect(TieRule(rawValue: raw) == rule)
    }
}

struct LeagueConfigTests {

    @Test func bundledConfigLoadsForPremierLeague() {
        let config = LeagueConfig.shared
        #expect(config.leagueId == "PL")
        #expect(config.teamsCount == 20)
        #expect(config.workerURL.scheme == "https")
        #expect(config.defaultTieRule == .rolloverRound)
    }
}
