import XCTest

/// Side-by-side mascot trial: the same screens and moods with the pika and with the UPA lynx.
/// Export with scripts/export-screenshots.sh; shots are named "NN_<mascot>_<screen>".
@MainActor
final class MascotComparisonTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
    }

    func testGallery() throws {
        launch(mascot: "pika", extra: ["-MascotGallery"])
        snap("00_both_gallery")
    }

    func testPika() throws { tour("pika") }
    func testLynx() throws { tour("lynx") }

    private func tour(_ mascot: String) {
        // Onboarding's first page: Scout says hi (idle), then a tap makes it happy.
        launch(mascot: mascot, onboarded: false)
        snap("01_\(mascot)_onboarding_idle")
        app.terminate()

        launch(mascot: mascot)
        XCTAssertTrue(app.tabBars.buttons["Scout"].waitForExistence(timeout: 20))
        snap("02_\(mascot)_home_idle")

        // Typing a question: thinking.
        let field = composer
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(ScreenshotTests.water)
        snap("03_\(mascot)_home_typing")

        // Searching the library: thinking; then the answer streaming in: writing; then done: happy.
        app.buttons["composer.send"].tap()
        Thread.sleep(forTimeInterval: 0.6)
        snap("04_\(mascot)_answer_searching", settle: 0)
        Thread.sleep(forTimeInterval: 1.8)
        snap("05_\(mascot)_answer_writing", settle: 0)
        waitForAnswer()
        for _ in 0..<4 { app.swipeDown(velocity: .fast) }
        snap("06_\(mascot)_answer_done")

        // An emergency question: alert.
        app.buttons["New chat"].tap()
        let field2 = composer
        XCTAssertTrue(field2.waitForExistence(timeout: 5))
        field2.tap()
        field2.typeText(ScreenshotTests.ankle)
        app.buttons["composer.send"].tap()
        waitForAnswer()
        for _ in 0..<4 { app.swipeDown(velocity: .fast) }
        snap("07_\(mascot)_answer_urgent")

        app.buttons["Emergency help"].tap()
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 5))
        snap("08_\(mascot)_sos_sheet")
        app.buttons["Close"].tap()
    }

    // MARK: - Helpers

    private func launch(mascot: String, onboarded: Bool = true, extra: [String] = []) {
        app = XCUIApplication()
        app.launchArguments = [
            "-ScreenshotMode", "YES",
            "-mascot", mascot,
            "-completedOnboarding", onboarded ? "YES" : "NO",
            "-readiness.asked", "YES", "-readiness.askedOffline", "YES", "-readiness.celebrated", "YES",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
        ] + extra
        app.launch()
        Thread.sleep(forTimeInterval: 1.5)
    }

    private func snap(_ name: String, settle: TimeInterval = 1.2) {
        if settle > 0 { Thread.sleep(forTimeInterval: settle) }
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private var composer: XCUIElement {
        let view = app.textViews.firstMatch
        return view.exists ? view : app.textFields.firstMatch
    }

    private func waitForAnswer() {
        let stop = app.buttons["Stop"]
        if stop.exists || stop.waitForExistence(timeout: 3) {
            let done = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: stop)
            wait(for: [done], timeout: 60)
        }
        if app.keyboards.firstMatch.exists { app.swipeDown() }
    }
}
