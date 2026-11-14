import XCTest

/// App Store screenshots and the App Preview walkthrough, run by `fastlane screenshots` and `fastlane previews`.
///
/// The app runs in ScreenshotMode: a demo library, scripted answers (fastlane/screenshot-fixtures) and Apple's
/// model treated as available, so every run produces the same shots. Screenshots are kept as attachments
/// named "NN_name"; scripts/export-screenshots.sh pulls them out of the result bundle.
@MainActor
final class ScreenshotTests: XCTestCase {
    private var app: XCUIApplication!

    static let ankle = "My friend rolled their ankle 6 miles from the trailhead. Is it broken, and can they walk out?"
    static let water = "How do I make water from a stream safe to drink?"

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = [
            "-ScreenshotMode", "YES",
            "-completedOnboarding", "YES",
            "-readiness.asked", "YES", "-readiness.askedOffline", "YES", "-readiness.celebrated", "YES",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL",
        ]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Scout"].waitForExistence(timeout: 20))
    }

    // MARK: - Screenshots (order = App Store order)

    func testScreenshots() throws {
        snap("08_home")

        ask(Self.ankle)
        waitForAnswer()
        scrollToTop()
        snap("01_answer")

        app.buttons["More"].tap()
        app.buttons["Emergency help"].tap()
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 5))
        snap("02_sos")
        app.buttons["Close"].tap()

        app.tabBars.buttons["Guide"].tap()
        XCTAssertTrue(app.navigationBars["Guide"].waitForExistence(timeout: 5))
        snap("03_guide")

        app.staticTexts["Field mode"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Field mode"].waitForExistence(timeout: 5))
        snap("04_field")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        let topic = app.staticTexts["Heat illness"].firstMatch
        scrollUntilHittable(topic)
        topic.tap()
        XCTAssertTrue(app.navigationBars["Heat illness"].waitForExistence(timeout: 5))
        snap("05_topic")

        app.tabBars.buttons["Saved"].tap()
        snap("06_saved")

        app.tabBars.buttons["Scout"].tap()
        app.buttons["More"].tap()
        app.buttons["New chat"].tap()
        ask(Self.water)
        waitForAnswer()
        // The chat rests at its end, where the sources are. Pull back a little so the answer shows above them.
        let window = app.windows.firstMatch
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
            .press(forDuration: 0.1, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.62)))
        snap("07_sources")
    }

    // MARK: - App Preview (recorded by scripts/record-preview.sh between the two markers)

    func testPreviewWalkthrough() throws {
        sleep(1)
        NSLog("PREVIEW_MARK start")
        sleep(1)
        ask(Self.ankle, slowly: true)
        waitForAnswer()
        scrollToTop()
        sleep(2)
        app.swipeUp(velocity: .slow)
        sleep(1)
        app.swipeDown(velocity: .slow)  // scrolling back up brings the minimized tab bar back

        app.tabBars.buttons["Guide"].tap()
        sleep(2)
        app.staticTexts["Field mode"].firstMatch.tap()
        sleep(2)
        app.navigationBars.buttons.element(boundBy: 0).tap()

        app.tabBars.buttons["Guide"].tap()
        app.buttons["Emergency help"].tap()
        sleep(3)
        NSLog("PREVIEW_MARK end")
    }

    // MARK: - Helpers

    private func snap(_ name: String) {
        Thread.sleep(forTimeInterval: 1.2)  // let animations settle
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private var composer: XCUIElement {
        let view = app.textViews.firstMatch
        return view.exists ? view : app.textFields.firstMatch
    }

    private func ask(_ question: String, slowly: Bool = false) {
        let field = composer
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        if slowly {
            // A few words at a time reads as typing without spending the preview's 30 seconds on it.
            let words = question.split(separator: " ")
            for start in stride(from: 0, to: words.count, by: 4) {
                field.typeText(words[start..<min(start + 4, words.count)].joined(separator: " ") + " ")
            }
        } else {
            field.typeText(question)
        }
        app.buttons["composer.send"].tap()
    }

    private func waitForAnswer() {
        XCTAssertTrue(app.buttons["Stop"].waitForExistence(timeout: 5))
        let done = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.buttons["Stop"])
        wait(for: [done], timeout: 60)
        if app.keyboards.firstMatch.exists { app.swipeDown() }
    }

    private func scrollToTop() {
        for _ in 0..<4 { app.swipeDown(velocity: .fast) }
    }

    private func scrollUntilHittable(_ element: XCUIElement) {
        for _ in 0..<8 where !(element.exists && element.isHittable) { app.swipeUp(velocity: .slow) }
    }
}
