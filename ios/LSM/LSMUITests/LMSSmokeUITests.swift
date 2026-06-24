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
}
