import XCTest

/// The full card: all 18 holes at once on the open Duo and on any iPhone held
/// sideways, picked with Full beside Hole and Nine. Scores entered on it are
/// the round's own, so the other views show them too. Saves screenshots.
final class FullCardUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }

    /// Sideways: today's sample round (three players, five holes) on the full
    /// card, a score added on the back nine, then the hole view shows it.
    @MainActor
    func testSidewaysFullCard() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-skipOnboarding", "-sampleRounds", "-startSideways", "full"]
        app.launch()
        let resume = app.buttons["resume-round"]
        XCTAssertTrue(resume.waitForExistence(timeout: 15), "Today's sample round should be offered to resume")
        resume.tap()
        XCTAssertTrue(app.buttons["finish-round"].waitForExistence(timeout: 5), "The round did not open")

        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(2)
        let front = app.otherElements["full-card-front"]
        guard front.waitForExistence(timeout: 5) else {
            // The closed Duo's outer screen may not turn sideways; any other iPhone must.
            XCTAssertTrue(Self.device.contains("Duo"), "Sideways should start on the full card")
            return
        }
        XCTAssertTrue(app.otherElements["full-card-back"].exists, "The full card should show the back nine too")
        XCTAssertTrue(app.buttons["score-0-1"].exists, "Hole 1 should be on the card")
        XCTAssertTrue(app.buttons["score-2-18"].exists, "Hole 18 should be on the card")
        XCTAssertTrue(app.otherElements["round-totals"].exists, "The half without the + and − should show the totals")
        sleep(1)
        capture("c1-sideways-full-card")

        // Score hole 12 on the back nine: the + and − move to that half.
        app.buttons["score-0-12"].tap()
        let plus = app.buttons.matching(identifier: "score-plus")
        XCTAssertEqual(plus.count, 1, "There should be one + on screen")
        plus.firstMatch.tap()
        let scored = app.buttons["score-0-12"].value as? String ?? ""
        XCTAssertFalse(scored.isEmpty || scored == "no score", "Hole 12 should have a score")
        sleep(1)
        capture("c2-sideways-full-card-back-nine")

        // The hole view shows the same score: it's one round.
        app.buttons["Hole"].firstMatch.tap()
        let value = app.staticTexts["hole-score-value-0"]
        XCTAssertTrue(value.waitForExistence(timeout: 5), "The hole view should open")
        XCTAssertEqual(value.label, scored, "The hole view should show the score entered on the full card")
    }

    /// The open Duo, drawn at its size on the Pro Max: a foursome's card with
    /// both nines side by side, then a score on the back nine.
    @MainActor
    func testOpenDuoFullCard() throws {
        guard Self.device.contains("Pro Max") else { return }
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launchArguments = ["-uiTesting", "-skipOnboarding", "-openDuoPreview", "-sampleCard", "-startDuoOpen", "full"]
        app.launch()
        XCTAssertTrue(app.otherElements["full-card-front"].waitForExistence(timeout: 15), "The open Duo should start on the full card")
        XCTAssertTrue(app.otherElements["full-card-back"].exists, "The full card should show the back nine too")
        XCTAssertTrue(app.buttons["score-3-18"].exists, "Every player's hole 18 should be on the card")
        let total = app.staticTexts["full-total-0"]
        XCTAssertTrue(total.exists, "The round's totals should be showing")
        let before = total.label
        sleep(1)
        capture("c3-open-duo-size-full-card")

        app.buttons["score-0-14"].tap()
        app.buttons["score-plus"].tap()
        sleep(1)
        XCTAssertNotEqual(app.staticTexts["full-total-0"].label, before, "The total should count the new score")
        capture("c4-open-duo-size-full-card-hole-14")
    }

    private static var device: String {
        ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] ?? ""
    }

    @MainActor
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
