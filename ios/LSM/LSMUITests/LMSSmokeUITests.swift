import XCTest

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

    private func attachScreenshot(named name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
