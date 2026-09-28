import XCTest

/// Walks the main screens in mock mode and saves a PNG of each to
/// `SCREENSHOT_DIR` on the host, for design review. Skipped unless the
/// variable is set, e.g.:
///
///     TEST_RUNNER_SCREENSHOT_DIR=/tmp/shots xcodebuild test -only-testing:HermesMobileUITests/ScreenshotTourUITests ...
final class ScreenshotTourUITests: XCTestCase {
    private var outputDirectory: URL!
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        guard let path = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"], !path.isEmpty else {
            throw XCTSkip("Set SCREENSHOT_DIR to capture the screenshot tour.")
        }
        continueAfterFailure = true
        outputDirectory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        app = XCUIApplication()
        app.launchEnvironment["UITEST_DEFAULTS_SUITE"] = "uitest.tour.\(UUID().uuidString)"
        app.launchEnvironment["UITEST_KEYCHAIN_SERVICE"] = "uitest.tour.\(UUID().uuidString)"
        app.launchEnvironment["UITEST_PAIRING_MODE"] = "mock"
        app.launch()
        pair()
    }

    @MainActor
    func testTour() throws {
        capture("01-chat")

        for (tab, name) in [("Team", "02-team"), ("Automations", "05-automations"), ("Library", "07-library")] {
            let button = app.tabBars.buttons[tab]
            guard button.waitForExistence(timeout: 5) else {
                XCTFail("Missing tab \(tab)")
                continue
            }
            button.tap()
            sleep(1)
            capture(name)

            switch tab {
            case "Team":
                if openFirst(identifierPrefix: "team.task.") { capture("03-task-detail"); goBack() }
                if tapIfExists(app.buttons["team.newTask"]) { capture("04-new-task"); dismissSheet() }
            case "Automations":
                if tapIfExists(app.buttons["automations.new"]) { capture("06-new-automation"); dismissSheet() }
            case "Library":
                if tapIfExists(app.buttons["Skills"]) { sleep(1); capture("08-library-skills") }
            default:
                break
            }
        }

        app.tabBars.buttons["Chat"].tap()
        if tapIfExists(app.buttons["chat.history"]) { capture("09-history"); dismissSheet() }
        if tapIfExists(app.buttons["Open settings"]) { capture("10-settings"); dismissSheet() }
    }

    // MARK: Helpers

    private func pair() {
        let manual = app.buttons["Enter Code Manually"]
        guard manual.waitForExistence(timeout: 8) else { return }
        manual.tap()
        let field = app.textFields["Setup code"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("ABCD-EFGH")
        app.buttons["Connect Hermes"].tap()
        let continueButton = app.buttons["Continue"]
        if continueButton.waitForExistence(timeout: 5) {
            continueButton.tap()
        }
        _ = app.tabBars.firstMatch.waitForExistence(timeout: 8)
        sleep(1)
    }

    private func capture(_ name: String) {
        let data = XCUIScreen.main.screenshot().pngRepresentation
        let url = outputDirectory.appendingPathComponent("\(name).png")
        XCTAssertNoThrow(try data.write(to: url))
    }

    @discardableResult
    private func tapIfExists(_ element: XCUIElement) -> Bool {
        guard element.waitForExistence(timeout: 3) else { return false }
        element.tap()
        sleep(1)
        return true
    }

    private func openFirst(identifierPrefix: String) -> Bool {
        let match = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", identifierPrefix))
            .firstMatch
        return tapIfExists(match)
    }

    private func goBack() {
        let back = app.navigationBars.buttons.element(boundBy: 0)
        if back.exists { back.tap() }
        sleep(1)
    }

    private func dismissSheet() {
        app.swipeDown(velocity: .fast)
        sleep(1)
        if app.sheets.firstMatch.exists || app.otherElements["sheet"].exists {
            app.swipeDown(velocity: .fast)
        }
    }
}
