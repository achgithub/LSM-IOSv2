import Foundation
import SwiftData

#if DEBUG
@MainActor
enum UITestPWAScenarioSeeder {
    private static let launchFlag = "-seed-pwa-e2e"
    private static let namePrefix = "[UIE2E]"
    private static let playerCount = 4

    static func seedIfRequested(context: ModelContext, entitlements: Entitlements) {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("-uitests"), args.contains(launchFlag) else { return }

        let env = ProcessInfo.processInfo.environment
        let scenario = env["LSM_UIE2E_SCENARIO_ID"] ?? "local"
        let tokens = (env["LSM_UIE2E_PLAYER_TOKENS"] ?? "")
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        guard tokens.count >= playerCount else { return }

        UserDefaults.standard.set("UITest Manager", forKey: ManagerSettings.nameKey)
        UserDefaults.standard.set(true, forKey: "pwaSubmissionsEnabled")
        entitlements.setDevTier(.leagues3)

        clearExistingSeedData(context: context)
        TutorialDataService.seedLeagueCaches()

        let members = (0..<playerCount).map { index -> RosterMember in
            let member = RosterMember(name: playerName(index: index, scenario: scenario))
            member.submissionTokenRaw = tokens[index]
            context.insert(member)
            return member
        }

        createGame(
            name: "\(namePrefix) PWA LMS \(scenario)",
            mode: .lms,
            gameToken: env["LSM_UIE2E_LMS_GAME_TOKEN"],
            fixtureIds: [910_001, 910_002],
            members: members,
            context: context
        )
        createGame(
            name: "\(namePrefix) PWA Predictor \(scenario)",
            mode: .predictor,
            gameToken: env["LSM_UIE2E_PREDICTOR_GAME_TOKEN"],
            fixtureIds: [920_001, 920_002, 920_003],
            members: members,
            context: context
        )

        try? context.save()
    }

    private static func clearExistingSeedData(context: ModelContext) {
        if let games = try? context.fetch(FetchDescriptor<Game>()) {
            for game in games where game.name.hasPrefix(namePrefix) {
                context.delete(game)
            }
        }
        if let members = try? context.fetch(FetchDescriptor<RosterMember>()) {
            for member in members where member.name.hasPrefix(namePrefix) {
                context.delete(member)
            }
        }
    }

    private static func createGame(
        name: String,
        mode: GameMode,
        gameToken: String?,
        fixtureIds: [Int],
        members: [RosterMember],
        context: ModelContext
    ) {
        let game = Game(
            name: name,
            season: Leagues.app.season,
            allowRepeats: true,
            leagueIds: [Leagues.demoLeagueId],
            isDemoData: true,
            mode: mode,
            predictorJokerEnabled: mode == .predictor
        )
        game.status = .active
        game.cloudGameTokenRaw = gameToken?.lowercased()
        context.insert(game)

        for (index, member) in members.enumerated() {
            let player = Player(name: member.name, game: game, entryNumber: index + 1)
            player.rosterMemberId = member.id
            context.insert(player)
            game.players.append(player)
        }

        let round = Round(
            roundNumber: 1,
            deadline: Date().addingTimeInterval(24 * 3600),
            fixtureIds: fixtureIds,
            game: game
        )
        context.insert(round)
        game.rounds.append(round)
    }

    private static func playerName(index: Int, scenario: String) -> String {
        "\(namePrefix) Player \(index + 1) \(scenario)"
    }
}
#endif
