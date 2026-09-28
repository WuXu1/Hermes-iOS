import XCTest

/// Walks the main screens in mock mode and saves a PNG of each to
/// `SCREENSHOT_DIR` on the host, for design review. Skipped unless the
/// variable is set, e.g.:
///
///     TEST_RUNNER_SCREENSHOT_DIR=/tmp/shots xcodebuild test -only-testing:HermesMobileUITests/ScreenshotTourUITests ...
final class ScreenshotTourUITests: XCTestCase {
    private var outputDirectory: URL!
    private var app: XCUIApplication!
    /// With LIVE_RELAY_URL and LIVE_PAIRING_CODE set, the tour pairs with a real relay instead of mocks.
    private var liveRelayURL: String?

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
        let environment = ProcessInfo.processInfo.environment
        liveRelayURL = environment["LIVE_RELAY_URL"].flatMap { $0.isEmpty ? nil : $0 }
        let liveCode = environment["LIVE_PAIRING_CODE"].flatMap { $0.isEmpty ? nil : $0 }
        if liveRelayURL == nil {
            app.launchEnvironment["UITEST_PAIRING_MODE"] = "mock"
        }
        app.launch()
        pair(code: liveCode ?? "ABCD-EFGH")
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
                if openFirst(identifierPrefix: "automations.job.") { capture("05b-job-detail"); goBack() }
                if tapIfExists(app.buttons["automations.new"]) {
                    capture("06-new-automation")
                    if tapIfExists(app.buttons["Custom"]) { capture("06b-new-automation-custom") }
                    dismissSheet()
                }
            case "Library":
                if openFirst(identifierPrefix: "library.memory.") { capture("07b-memory"); goBack() }
                if tapIfExists(app.buttons["Skills"]) { sleep(1); capture("08-library-skills") }
            default:
                break
            }
        }

        app.tabBars.buttons["Chat"].tap()
        if tapIfExists(app.buttons["chat.history"]) { capture("09-history"); dismissSheet() }
        if tapIfExists(app.buttons["Open settings"]) { capture("10-settings"); dismissSheet() }
        // Chat steps change the account's shared current chat; mock mode only.
        if liveRelayURL == nil {
            let composer = app.textFields["chat.composer"]
            if composer.waitForExistence(timeout: 3) {
                composer.tap()
                composer.typeText("/clear")
                if tapIfExists(app.buttons["Send message"]), tapIfExists(app.buttons["Clear"]) {
                    sleep(1)
                    capture("11-chat-empty")
                }
            }
            if tapIfExists(app.buttons["chat.new"]) {
                if tapIfExists(app.buttons["chat.assign"]) {
                    if tapIfExists(app.buttons["Researcher"]) {
                        app.typeText("Compare the three best e-bikes under £2,000")
                        capture("12-chat-assign")
                    }
                }
            }
        }
    }

    // MARK: Helpers

    private func pair(code: String) {
        let manual = app.buttons["Enter Code Manually"]
        guard manual.waitForExistence(timeout: 8) else { return }
        manual.tap()
        if let liveRelayURL {
            let relayField = app.textFields["Relay URL"]
            XCTAssertTrue(relayField.waitForExistence(timeout: 5))
            relayField.tap()
            relayField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 60))
            relayField.typeText(liveRelayURL)
        }
        let field = app.textFields["Setup code"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(code)
        app.buttons["Connect Hermes"].tap()
        // Pairing success, then (for real devices) permissions onboarding, each end in Continue.
        let continueButton = app.buttons["Continue"]
        for _ in 0 ..< 3 {
            guard continueButton.waitForExistence(timeout: liveRelayURL == nil ? 5 : 20) else { break }
            continueButton.tap()
            sleep(2)
            if app.tabBars.firstMatch.exists { break }
        }
        _ = app.tabBars.firstMatch.waitForExistence(timeout: liveRelayURL == nil ? 8 : 20)
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
        for label in ["Done", "Cancel", "Close"] {
            let button = app.navigationBars.buttons[label].exists ? app.navigationBars.buttons[label] : app.buttons[label]
            if button.exists, button.isHittable {
                button.tap()
                sleep(1)
                return
            }
        }
        app.swipeDown(velocity: .fast)
        sleep(1)
    }
}
