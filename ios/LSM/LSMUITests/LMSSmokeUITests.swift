import XCTest
import Foundation

/// Network-free launch smoke test. Verifies the app boots, the first-run
/// onboarding works, and the main tab bar appears. Ads + consent are skipped via
/// the `-uitests` launch flag so no system dialogs (ATT / UMP) can make this
/// flaky, and no screen that needs the network is touched.
final class LMSSmokeUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchOnboardingAndTabsAppear() {
        let app = XCUIApplication()
        // -uitests: app skips ad bootstrap/consent. Force English so the tab
        // labels are deterministic regardless of the simulator's language.
        app.launchArguments += ["-uitests", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        // A fresh install shows the manager-name prompt after the launch splash.
        // (On a re-run where the name is already saved it won't appear — handled.)
        let nameField = app.textFields.firstMatch
        if nameField.waitForExistence(timeout: 15) {
            nameField.tap()
            nameField.typeText("UITester")
            app.buttons["Continue"].firstMatch.tap()
        }

        // The five-tab navigation should now be present and interactive.
        XCTAssertTrue(
            app.tabBars.buttons["Games"].waitForExistence(timeout: 15),
            "Main tab bar (Games) did not appear after launch/onboarding"
        )
    }

    /// Live data test (v2 cut-over): navigates to Standings and Matches and
    /// confirms real rows load from the v2 regional Workers. Unlike the smoke
    /// test above this does NOT avoid the network — it's the whole point — but it
    /// still passes `-uitests` so ad/consent dialogs stay out of the way.
    @MainActor
    func testLeaguesLoadFromV2Workers() {
        let app = XCUIApplication()
        app.launchArguments += ["-uitests", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        let nameField = app.textFields.firstMatch
        if nameField.waitForExistence(timeout: 15) {
            nameField.tap()
            nameField.typeText("UITester")
            app.buttons["Continue"].firstMatch.tap()
        }

        XCTAssertTrue(
            app.tabBars.buttons["Standings"].waitForExistence(timeout: 15),
            "Standings tab never appeared"
        )

        // --- Standings: should load a league table from the UK Worker. ---
        app.tabBars.buttons["Standings"].tap()
        XCTAssertTrue(
            app.navigationBars["Standings"].waitForExistence(timeout: 10),
            "Standings screen did not open"
        )
        // Wait for the live fetch to resolve into table rows.
        let firstStandingCell = app.cells.firstMatch
        XCTAssertTrue(
            firstStandingCell.waitForExistence(timeout: 25),
            "No standings rows loaded from the v2 Worker"
        )
        XCTAssertFalse(
            app.staticTexts["Couldn't load standings"].exists,
            "Standings showed a load error instead of data"
        )
        attachScreenshot(named: "Standings")

        // --- Matches: should load fixtures/scores from the same Worker. ---
        app.tabBars.buttons["Matches"].tap()
        let firstMatchCell = app.cells.firstMatch
        XCTAssertTrue(
            firstMatchCell.waitForExistence(timeout: 25),
            "No match rows loaded from the v2 Worker"
        )
        attachScreenshot(named: "Matches")
    }

    /// Phase-1 Predictor smoke: create a Predictor game via the New Game mode
    /// picker, confirm it lands on the Games list with the "Predictor" badge,
    /// and that its detail screen opens with the Standings entry point —
    /// covers the mode discriminator + new-game flow + routing end-to-end,
    /// without touching the network.
    @MainActor
    func testCreatePredictorGame() {
        let app = XCUIApplication()
        app.launchArguments += ["-uitests", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        let nameField = app.textFields.firstMatch
        if nameField.waitForExistence(timeout: 15) {
            nameField.tap()
            nameField.typeText("UITester")
            app.buttons["Continue"].firstMatch.tap()
        }

        XCTAssertTrue(
            app.tabBars.buttons["Games"].waitForExistence(timeout: 15),
            "Games tab never appeared"
        )
        app.tabBars.buttons["Games"].tap()

        app.navigationBars.buttons["New Game"].firstMatch.tap()

        XCTAssertTrue(
            app.staticTexts["Predictor"].waitForExistence(timeout: 10),
            "Predictor mode option never appeared in the New Game picker"
        )
        app.staticTexts["Predictor"].tap()

        let nameTextField = app.textFields["Game name"]
        XCTAssertTrue(nameTextField.waitForExistence(timeout: 10), "Predictor form never appeared")
        nameTextField.tap()
        nameTextField.typeText("Predictor Test")

        app.navigationBars.buttons["Create"].tap()

        XCTAssertTrue(
            app.staticTexts["Predictor Test"].waitForExistence(timeout: 10),
            "New Predictor game never appeared on the Games list"
        )
        XCTAssertTrue(app.staticTexts["Predictor"].waitForExistence(timeout: 5), "Predictor mode badge missing on GameCard")
        attachScreenshot(named: "PredictorGameCard")

        app.staticTexts["Predictor Test"].tap()
        XCTAssertTrue(
            app.buttons["Standings"].waitForExistence(timeout: 10),
            "Predictor game detail screen never opened"
        )
        attachScreenshot(named: "PredictorGameDetail")
    }

    /// Phase-2 Cloud Backup/Publish render smoke: flips the DEBUG-only
    /// "Simulate tier" picker to a cloud-entitled tier (no network/purchase
    /// needed), confirms the gated UI actually renders both there and inside
    /// a Predictor game's detail screen — i.e. `@Environment(Entitlements.self)`
    /// really is injected at both call sites and the views don't crash on
    /// appear. Settings is now a list of pushed sub-screens (Apple-style),
    /// so this drills into Subscription (to flip the tier) and Backup & Cloud
    /// (to see the gated UI) rather than reading a flat Settings screen.
    @MainActor
    func testCloudBundleUIRendersWhenEntitled() {
        let app = XCUIApplication()
        app.launchArguments += ["-uitests", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        let nameField = app.textFields.firstMatch
        if nameField.waitForExistence(timeout: 15) {
            nameField.tap()
            nameField.typeText("UITester")
            app.buttons["Continue"].firstMatch.tap()
        }

        XCTAssertTrue(app.tabBars.buttons["Settings"].waitForExistence(timeout: 15))
        app.tabBars.buttons["Settings"].tap()

        app.staticTexts["Backup & Cloud"].tap()
        // Not entitled yet — the upsell row should be showing.
        XCTAssertTrue(app.buttons["Unlock Cloud Backup"].waitForExistence(timeout: 10))
        app.navigationBars.buttons.firstMatch.tap()   // back to Settings

        app.staticTexts["Subscription"].tap()
        let tierPicker = app.buttons["Simulate tier, Free"]
        XCTAssertTrue(tierPicker.waitForExistence(timeout: 10), "Dev tier simulator never appeared")
        tierPicker.tap()
        let leagues3Option = app.buttons["3 Leagues"]
        XCTAssertTrue(leagues3Option.waitForExistence(timeout: 10), "3 Leagues tier option never appeared")
        leagues3Option.tap()
        app.navigationBars.buttons.firstMatch.tap()   // back to Settings

        app.staticTexts["Backup & Cloud"].tap()
        XCTAssertTrue(app.buttons["Back Up Now"].waitForExistence(timeout: 10), "Cloud Backup section didn't switch to the entitled state")
        XCTAssertTrue(app.buttons["Restore…"].exists)
        attachScreenshot(named: "CloudBackupEntitled")

        // Now confirm the gate also renders inside a Predictor game.
        app.tabBars.buttons["Games"].tap()
        app.navigationBars.buttons["New Game"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Predictor"].waitForExistence(timeout: 10))
        app.staticTexts["Predictor"].tap()
        let nameTextField = app.textFields["Game name"]
        XCTAssertTrue(nameTextField.waitForExistence(timeout: 10))
        nameTextField.tap()
        nameTextField.typeText("Publish Test")
        app.navigationBars.buttons["Create"].tap()

        XCTAssertTrue(app.staticTexts["Publish Test"].waitForExistence(timeout: 10))
        app.staticTexts["Publish Test"].tap()

        let publishButton = app.buttons["Publish League…"]
        XCTAssertTrue(publishButton.waitForExistence(timeout: 10), "Publish action never appeared on an entitled Predictor game")
        publishButton.tap()

        XCTAssertTrue(app.navigationBars["Publish League"].waitForExistence(timeout: 10), "PublishPredictorView never opened")
        attachScreenshot(named: "PublishPredictorView")
    }

    /// Pre-season PWA rehearsal: seeds one LMS game and one Predictor game in
    /// the iOS manager app, then submits as four player-link users through the
    /// same Worker routes the PWA uses. The test stops with pending submissions
    /// visible so a manual run can continue from the real manager queue.
    @MainActor
    func testPWAFourUserSetupForLMSAndPredictor() throws {
        let scenario = "ios-\(UUID().uuidString.prefix(8).lowercased())"
        let playerNames = (1...4).map { "[UIE2E] Player \($0) \(scenario)" }
        let managerToken = UUID().uuidString.lowercased()
        let tokens = try playerNames.map { try mintSubmissionLink(playerName: $0, managerToken: managerToken) }
        let lmsGameToken = UUID().uuidString.lowercased()
        let predictorGameToken = UUID().uuidString.lowercased()

        let lmsFixtures = [
            fixture(910_001, "Albion", "Borough"),
            fixture(910_002, "County", "Dynamos"),
        ]
        let predictorFixtures = [
            fixture(920_001, "Eagles", "Forest"),
            fixture(920_002, "Harbour", "Junction"),
            fixture(920_003, "Kings", "Lions"),
        ]
        let eligibleTeams = [
            team(1001, "Albion"),
            team(1002, "Borough"),
            team(1003, "County"),
            team(1004, "Dynamos"),
        ]

        try pushRound(
            gameToken: lmsGameToken,
            mode: "lms",
            fixtures: lmsFixtures,
            jokerEnabled: false,
            managerToken: managerToken,
            tokens: tokens,
            eligibleTeams: eligibleTeams
        )
        try pushRound(
            gameToken: predictorGameToken,
            mode: "predictor",
            fixtures: predictorFixtures,
            jokerEnabled: true,
            managerToken: managerToken,
            tokens: tokens,
            eligibleTeams: []
        )

        for (index, token) in tokens.enumerated() {
            try assertPlayerLink(token, containsGameTokens: [lmsGameToken, predictorGameToken])
            try submitPlayer(
                token: token,
                gameToken: lmsGameToken,
                payload: [
                    "teamId": 1001 + index,
                    "teamName": eligibleTeams[index]["name"] as? String ?? "Team \(index + 1)",
                ]
            )
            try submitPlayer(
                token: token,
                gameToken: predictorGameToken,
                payload: [
                    "scores": predictorFixtures.enumerated().map { fixtureIndex, item in
                        [
                            "fixtureId": item["fixtureId"] as? Int ?? 0,
                            "home": (index + fixtureIndex) % 4,
                            "away": (index + fixtureIndex + 1) % 3,
                            "isJoker": fixtureIndex == index % predictorFixtures.count,
                        ]
                    },
                ]
            )
        }

        let app = XCUIApplication()
        app.launchArguments += [
            "-uitests",
            "-seed-pwa-e2e",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
        ]
        app.launchEnvironment["LSM_UIE2E_SCENARIO_ID"] = scenario
        app.launchEnvironment["LSM_UIE2E_PLAYER_TOKENS"] = tokens.joined(separator: ",")
        app.launchEnvironment["LSM_UIE2E_LMS_GAME_TOKEN"] = lmsGameToken
        app.launchEnvironment["LSM_UIE2E_PREDICTOR_GAME_TOKEN"] = predictorGameToken
        app.launch()

        completeOnboardingIfNeeded(app)

        XCTAssertTrue(app.tabBars.buttons["Games"].waitForExistence(timeout: 20), "Games tab never appeared")
        app.tabBars.buttons["Games"].tap()

        let lmsName = "[UIE2E] PWA LMS \(scenario)"
        openSubmissionQueue(app, gameName: lmsName, playerNames: playerNames, screenshotName: "PWA-LMS-Queue")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars.buttons["Games"].waitForExistence(timeout: 5), "Back button to Games missing")
        app.navigationBars.buttons["Games"].tap()

        let predictorName = "[UIE2E] PWA Predictor \(scenario)"
        openSubmissionQueue(app, gameName: predictorName, playerNames: playerNames, screenshotName: "PWA-Predictor-Queue")
    }

    /// Players tab smoke: add a player, confirm the new lean list (search +
    /// filters visible, row renders), then open the detail screen and confirm
    /// the header/groups/remove sections render without crashing.
    @MainActor
    func testPlayersListAndDetailRender() {
        let app = XCUIApplication()
        app.launchArguments += ["-uitests", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        completeOnboardingIfNeeded(app)

        XCTAssertTrue(app.tabBars.buttons["Players"].waitForExistence(timeout: 15), "Players tab never appeared")
        app.tabBars.buttons["Players"].tap()

        XCTAssertTrue(app.navigationBars["Players"].waitForExistence(timeout: 10), "Players screen did not open")
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 10), "Search field missing from Players list")

        let playerName = "UITest Player \(UUID().uuidString.prefix(6))"
        app.navigationBars.buttons["Add player"].tap()
        let nameField = app.alerts.textFields.firstMatch
        XCTAssertTrue(nameField.waitForExistence(timeout: 10), "Add player alert never appeared")
        nameField.tap()
        nameField.typeText(playerName)
        app.alerts.buttons["Add"].tap()
        attachScreenshot(named: "PlayersList")

        let row = app.staticTexts[playerName]
        XCTAssertTrue(row.waitForExistence(timeout: 10), "New player never appeared in the list")
        row.tap()

        XCTAssertTrue(app.navigationBars[playerName].waitForExistence(timeout: 10), "Player detail screen never opened")
        XCTAssertTrue(app.staticTexts["Not in any groups yet."].waitForExistence(timeout: 5), "Groups section missing")
        XCTAssertTrue(app.buttons["Remove Player"].waitForExistence(timeout: 5), "Remove Player action missing")
        attachScreenshot(named: "PlayerDetail")
    }

    /// End-to-end manual-fixture flow inside a Predictor game — the concept
    /// was previously only exercised (manually) in LMS. Confirms
    /// `OpenRoundView`/`AddManualFixtureSheet` (moved to Shared/Rounds since
    /// they're mode-agnostic) actually work when driven from
    /// `PredictorGameDetailView`: add a hand-typed fixture, open a round on
    /// it, enter a prediction, enter a result, and close the round.
    @MainActor
    func testManualFixturePredictorFlow() {
        let app = XCUIApplication()
        app.launchArguments += ["-uitests", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        completeOnboardingIfNeeded(app)

        let suffix = UUID().uuidString.prefix(6)
        let player1 = "MF Player A \(suffix)"
        let player2 = "MF Player B \(suffix)"

        // --- Create two roster players. ---
        XCTAssertTrue(app.tabBars.buttons["Players"].waitForExistence(timeout: 15), "Players tab never appeared")
        app.tabBars.buttons["Players"].tap()
        let search = app.searchFields.firstMatch
        for name in [player1, player2] {
            app.navigationBars.buttons["Add player"].tap()
            let nameField = app.alerts.textFields.firstMatch
            XCTAssertTrue(nameField.waitForExistence(timeout: 10), "Add player alert never appeared")
            nameField.tap()
            nameField.typeText(name)
            app.alerts.buttons["Add"].tap()
            // The demo-seeded roster pushes new (alphabetically-sorted) rows
            // off the lazy-loaded list — filter via search rather than
            // relying on the row being on-screen.
            XCTAssertTrue(search.waitForExistence(timeout: 10), "Search field missing from Players list")
            search.tap()
            search.typeText(name)
            XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 10), "\(name) never appeared in Players list")
            search.buttons["Clear text"].tap()
        }

        // --- Create the Predictor game. ---
        app.tabBars.buttons["Games"].tap()
        app.navigationBars.buttons["New Game"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Predictor"].waitForExistence(timeout: 10), "Predictor mode option never appeared")
        app.staticTexts["Predictor"].tap()
        let gameName = "Manual Fixture Predictor \(suffix)"
        let nameTextField = app.textFields["Game name"]
        XCTAssertTrue(nameTextField.waitForExistence(timeout: 10), "Predictor form never appeared")
        nameTextField.tap()
        nameTextField.typeText(gameName)
        app.navigationBars.buttons["Create"].tap()

        XCTAssertTrue(app.staticTexts[gameName].waitForExistence(timeout: 10), "New Predictor game never appeared on Games list")
        app.staticTexts[gameName].tap()
        XCTAssertTrue(app.buttons["Standings"].waitForExistence(timeout: 10), "Predictor game detail screen never opened")

        // --- Add the two roster players into this game. ---
        app.buttons["Add Players"].tap()
        let addPlayersSearch = app.searchFields.firstMatch
        XCTAssertTrue(addPlayersSearch.waitForExistence(timeout: 10), "Search field missing from Add Players sheet")
        for name in [player1, player2] {
            addPlayersSearch.tap()
            addPlayersSearch.typeText(name)
            let row = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", name)).firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 10), "\(name) missing from Add Players sheet")
            row.tap()
            addPlayersSearch.buttons["Clear text"].tap()
        }
        app.buttons["Done"].tap()

        // --- Open a round, adding a manual (hand-typed) fixture. ---
        let openMatchday = app.buttons["Open Matchday"]
        XCTAssertTrue(openMatchday.waitForExistence(timeout: 10), "Open Matchday button never appeared")
        openMatchday.tap()

        let addManualFixture = app.buttons["Add Manual Fixture"]
        XCTAssertTrue(addManualFixture.waitForExistence(timeout: 25), "Add Manual Fixture button never appeared (fixtures may not have loaded)")
        addManualFixture.tap()

        XCTAssertTrue(app.navigationBars["Add Manual Fixture"].waitForExistence(timeout: 10), "AddManualFixtureSheet never opened")
        let homeField = app.textFields["Home team"]
        let awayField = app.textFields["Away team"]
        XCTAssertTrue(homeField.waitForExistence(timeout: 10))
        homeField.tap()
        homeField.typeText("UITest Rovers \(suffix)")
        awayField.tap()
        awayField.typeText("UITest Athletic \(suffix)")
        app.navigationBars.buttons["Add"].tap()

        // Back in OpenRoundView — the manual fixture is auto-selected, so
        // "Open" should now be enabled (2 active players, 1 fixture picked).
        let openButton = app.navigationBars.buttons["Open"]
        XCTAssertTrue(openButton.waitForExistence(timeout: 10), "Open button never appeared")
        XCTAssertTrue(openButton.isEnabled, "Open button stayed disabled after adding a manual fixture")
        openButton.tap()

        // --- Enter a prediction for each player on the manual fixture. ---
        let enterPredictions = app.buttons["Enter Predictions"]
        XCTAssertTrue(enterPredictions.waitForExistence(timeout: 10), "Enter Predictions button never appeared after opening the round")
        enterPredictions.tap()

        let homePlus = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH 'predictionHome-' AND identifier ENDSWITH '-plus'"
        )).firstMatch
        XCTAssertTrue(homePlus.waitForExistence(timeout: 10), "Prediction score stepper never appeared — manual fixture missing from Predictions entry")
        homePlus.tap() // player 1: predicts 1-0

        let playerPicker = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Player,'")).firstMatch
        XCTAssertTrue(playerPicker.waitForExistence(timeout: 10), "Player picker never appeared")
        playerPicker.tap()
        let player2MenuItem = app.buttons[player2]
        XCTAssertTrue(player2MenuItem.waitForExistence(timeout: 5), "\(player2) never appeared in the player picker menu")
        player2MenuItem.tap()

        let awayPlus = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH 'predictionAway-' AND identifier ENDSWITH '-plus'"
        )).firstMatch
        XCTAssertTrue(awayPlus.waitForExistence(timeout: 10), "Prediction score stepper never appeared for \(player2)")
        awayPlus.tap() // player 2: predicts 0-1
        attachScreenshot(named: "ManualFixturePredictions")

        app.navigationBars.buttons["Done"].tap()

        // --- Enter the result and close the round. ---
        let enterResults = app.buttons["Enter Results / Close"]
        XCTAssertTrue(enterResults.waitForExistence(timeout: 10), "Enter Results / Close button never appeared")
        enterResults.tap()

        let enterResult = app.buttons["Enter result"]
        XCTAssertTrue(enterResult.waitForExistence(timeout: 10), "Enter result button never appeared for the manual fixture")
        enterResult.tap()

        let closeRound = app.buttons["Close Round"]
        XCTAssertTrue(closeRound.waitForExistence(timeout: 10))
        XCTAssertTrue(closeRound.isEnabled, "Close Round stayed disabled after entering a result for the manual fixture")
        closeRound.tap()

        // A confirmation sheet appears unless previously suppressed on this device.
        let confirmClose = app.sheets.buttons["Close Round"]
        if confirmClose.waitForExistence(timeout: 5) {
            confirmClose.tap()
        }

        // Back on game detail: the round closed without crashing and the
        // manual fixture scored — Standings should reflect the new points.
        XCTAssertTrue(app.buttons["Standings"].waitForExistence(timeout: 10), "Game detail never returned after closing the round")
        attachScreenshot(named: "ManualFixtureRoundClosed")
    }

    /// Verifies the downgrade-safety fix: a league already used by an active
    /// game stays fully usable after a subscription downgrade (no forced
    /// blocking screen, Create still works there), while starting a game in a
    /// *different*, not-yet-active league beyond the new allowance is blocked
    /// with an inline message instead of silently deleting anything.
    @MainActor
    func testLeagueAllowanceProtectsActiveGamesOnDowngrade() {
        let app = XCUIApplication()
        app.launchArguments += ["-uitests", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        completeOnboardingIfNeeded(app)

        // Bump to a 3-league tier and enable a second league.
        XCTAssertTrue(app.tabBars.buttons["Settings"].waitForExistence(timeout: 15))
        app.tabBars.buttons["Settings"].tap()
        app.staticTexts["Subscription"].tap()
        let tierPicker = app.buttons["Simulate tier, Free"]
        XCTAssertTrue(tierPicker.waitForExistence(timeout: 10), "Dev tier simulator never appeared")
        tierPicker.tap()
        app.buttons["3 Leagues"].tap()
        app.navigationBars.buttons.firstMatch.tap() // back to Settings

        app.staticTexts["Leagues"].tap()
        let championship = app.buttons["England — Championship"]
        XCTAssertTrue(championship.waitForExistence(timeout: 10), "Championship row never appeared")
        championship.tap()
        app.navigationBars.buttons.firstMatch.tap() // back to Settings

        // Create a game in the Premier League (the original, already-enabled
        // league) so it becomes "active" — this is the league that must
        // survive a downgrade.
        app.tabBars.buttons["Games"].tap()
        app.navigationBars.buttons["New Game"].firstMatch.tap()
        app.staticTexts["Last Man Standing"].tap()
        let nameField = app.textFields["Game name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 10), "LMS form never appeared")
        nameField.tap()
        nameField.typeText("Downgrade Test Game")
        app.buttons["England — Premier League"].tap() // select PL only (multi-league picker now visible)
        app.navigationBars.buttons["Create"].tap()
        XCTAssertTrue(app.staticTexts["Downgrade Test Game"].waitForExistence(timeout: 10), "Game never appeared on Games list")

        // Downgrade below the leagues now enabled (2 enabled, Free allows 1).
        app.tabBars.buttons["Settings"].tap()
        app.staticTexts["Subscription"].tap()
        app.buttons["Simulate tier, 3 Leagues"].tap()
        app.buttons["Free"].tap()
        app.navigationBars.buttons.firstMatch.tap()

        // No forced blocking screen — the tab bar must still be there and
        // interactive immediately after the downgrade.
        XCTAssertTrue(app.tabBars.buttons["Games"].waitForExistence(timeout: 10), "App got blocked after downgrade instead of staying usable")
        app.tabBars.buttons["Games"].tap()
        XCTAssertTrue(app.staticTexts["Downgrade Test Game"].waitForExistence(timeout: 10), "Existing game vanished after downgrade")

        // The already-active league (PL) must still be usable for a new game.
        app.navigationBars.buttons["New Game"].firstMatch.tap()
        app.staticTexts["Last Man Standing"].tap()
        let nameField2 = app.textFields["Game name"]
        XCTAssertTrue(nameField2.waitForExistence(timeout: 10))
        nameField2.tap()
        nameField2.typeText("Second PL Game")
        app.buttons["England — Premier League"].tap()
        let createButton = app.navigationBars.buttons["Create"]
        XCTAssertTrue(createButton.isEnabled, "Create disabled for an already-active league after downgrade — live game continuity broken")
        createButton.tap()
        XCTAssertTrue(app.staticTexts["Second PL Game"].waitForExistence(timeout: 10), "Could not create a second game in the already-active league after downgrade")
        attachScreenshot(named: "DowngradeStillUsable")

        // A DIFFERENT, not-yet-active league (Championship) beyond the new
        // Free allowance must be blocked — Create disabled, inline message shown.
        app.navigationBars.buttons["New Game"].firstMatch.tap()
        app.staticTexts["Last Man Standing"].tap()
        let nameField3 = app.textFields["Game name"]
        XCTAssertTrue(nameField3.waitForExistence(timeout: 10))
        nameField3.tap()
        nameField3.typeText("Should Not Create")
        app.buttons["England — Championship"].tap()
        XCTAssertFalse(app.navigationBars.buttons["Create"].isEnabled, "Create should be disabled for a new, over-allowance league after downgrade")
        XCTAssertTrue(
            app.staticTexts["Your plan doesn't cover an extra league right now. Leagues already in use by another game stay available to pick from — upgrade to add a new one."].waitForExistence(timeout: 5),
            "Over-allowance explanation footer never appeared"
        )
        attachScreenshot(named: "DowngradeBlockedNewLeague")
    }

    private func attachScreenshot(named name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func completeOnboardingIfNeeded(_ app: XCUIApplication) {
        let nameField = app.textFields.firstMatch
        if nameField.waitForExistence(timeout: 15) {
            nameField.tap()
            nameField.typeText("UITest Manager")
            app.buttons["Continue"].firstMatch.tap()
        }
    }

    @MainActor
    private func openSubmissionQueue(
        _ app: XCUIApplication,
        gameName: String,
        playerNames: [String],
        screenshotName: String
    ) {
        let game = app.staticTexts[gameName]
        XCTAssertTrue(game.waitForExistence(timeout: 15), "\(gameName) did not appear on the Games list")
        game.tap()

        let queueButton = app.buttons["Submission Queue"]
        XCTAssertTrue(queueButton.waitForExistence(timeout: 10), "Submission Queue button missing for \(gameName)")
        queueButton.tap()

        XCTAssertTrue(app.navigationBars["Submission Queue"].waitForExistence(timeout: 10), "Submission Queue did not open")
        XCTAssertTrue(
            app.buttons["Approve all pending (4)"].waitForExistence(timeout: 20),
            "Four pending submissions did not appear for \(gameName)"
        )
        for playerName in playerNames {
            XCTAssertTrue(app.staticTexts[playerName].exists, "\(playerName) missing from \(gameName) queue")
        }
        attachScreenshot(named: screenshotName)
    }

    private func mintSubmissionLink(playerName: String, managerToken: String) throws -> String {
        let json = try requestJSON(path: "/links", method: "POST", body: [
            "playerName": playerName,
            "managerToken": managerToken,
        ])
        guard let dict = json as? [String: Any], let token = dict["token"] as? String else {
            throw UITestAPIError.malformedResponse("Missing token for \(playerName)")
        }
        return token.lowercased()
    }

    private func pushRound(
        gameToken: String,
        mode: String,
        fixtures: [[String: Any]],
        jokerEnabled: Bool,
        managerToken: String,
        tokens: [String],
        eligibleTeams: [[String: Any]]
    ) throws {
        let players = tokens.map {
            [
                "token": $0,
                "localPlayerId": UUID().uuidString.lowercased(),
                "eligibleTeams": eligibleTeams,
            ] as [String: Any]
        }
        try postJSON(path: "/games/\(gameToken)/push", body: [
            "mode": mode,
            "roundNumber": 1,
            "deadline": ISO8601DateFormatter().string(from: Date().addingTimeInterval(24 * 3600)),
            "fixtures": fixtures,
            "jokerEnabled": jokerEnabled,
            "managerSuffix": NSNull(),
            "managerToken": managerToken,
            "players": players,
        ])
    }

    private func assertPlayerLink(_ token: String, containsGameTokens expectedTokens: [String]) throws {
        let json = try requestJSON(path: "/s/\(token)", method: "GET")
        guard let dict = json as? [String: Any],
              let games = dict["games"] as? [[String: Any]] else {
            throw UITestAPIError.malformedResponse("Missing games for player token \(token)")
        }
        let actual = Set(games.compactMap { $0["gameToken"] as? String })
        for expected in expectedTokens {
            XCTAssertTrue(actual.contains(expected), "PWA link \(token) did not include game \(expected)")
        }
    }

    private func submitPlayer(token: String, gameToken: String, payload: [String: Any]) throws {
        try postJSON(path: "/s/\(token)/games/\(gameToken)", body: payload)
    }

    private func fixture(_ id: Int, _ home: String, _ away: String) -> [String: Any] {
        [
            "fixtureId": id,
            "home": home,
            "away": away,
            "kickoff": ISO8601DateFormatter().string(from: Date().addingTimeInterval(48 * 3600)),
        ]
    }

    private func team(_ id: Int, _ name: String) -> [String: Any] {
        ["id": id, "name": name]
    }

    @discardableResult
    private func postJSON(path: String, body: [String: Any]) throws -> Any {
        try requestJSON(path: path, method: "POST", body: body)
    }

    private func requestJSON(path: String, method: String, body: [String: Any]? = nil) throws -> Any {
        let data = try request(path: path, method: method, body: body)
        return try JSONSerialization.jsonObject(with: data)
    }

    private func request(path: String, method: String, body: [String: Any]? = nil) throws -> Data {
        guard let url = URL(string: "https://lsm-uk-worker.sportsmanager.workers.dev\(path)") else {
            throw UITestAPIError.badURL(path)
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<(Data, URLResponse?), Error>?
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                result = .failure(error)
            } else {
                result = .success((data ?? Data(), response))
            }
            semaphore.signal()
        }.resume()
        semaphore.wait()

        guard let result else {
            throw UITestAPIError.malformedResponse("No response for \(path)")
        }
        let (data, response) = try result.get()
        guard let http = response as? HTTPURLResponse else {
            throw UITestAPIError.malformedResponse("No HTTP response for \(path)")
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? ""
            throw UITestAPIError.httpStatus(http.statusCode, message)
        }
        return data
    }

    private enum UITestAPIError: Error, CustomStringConvertible {
        case badURL(String)
        case httpStatus(Int, String)
        case malformedResponse(String)

        var description: String {
            switch self {
            case .badURL(let path):
                return "Bad URL: \(path)"
            case .httpStatus(let status, let body):
                return "HTTP \(status): \(body)"
            case .malformedResponse(let message):
                return message
            }
        }
    }
}
