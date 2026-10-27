import XCTest

/// Walks through a round the way a golfer would and saves screenshots of
/// each layout. The screenshots come out of the automatic checks on GitHub.
final class ScorecardFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }

    @MainActor
    func testScoreAHoleAndCaptureLayouts() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()

        // Course list
        let course = app.buttons["course-pompano-pines"]
        XCTAssertTrue(course.waitForExistence(timeout: 15), "Pompano Beach Pines is missing from the course list")
        capture("1-course-list")
        course.tap()

        // New round
        let start = app.buttons["start-round"]
        XCTAssertTrue(start.waitForExistence(timeout: 5), "The Start Round button is missing")
        start.tap()

        // Score hole 1 (par 5): first tap jumps to par, second adds one
        let firstScore = app.buttons["score-0-1"]
        XCTAssertTrue(firstScore.waitForExistence(timeout: 5), "The score card did not appear")
        firstScore.tap()
        let plus = app.buttons["score-plus"]
        plus.tap()
        plus.tap()
        XCTAssertEqual(app.staticTexts["nine-total-0"].label, "6", "Front nine total should be 6 after scoring hole 1")
        let mapPane = app.otherElements["map-pane"]
        if mapPane.exists {
            // Wide layout from the start (open iPhone Duo): card and map side by side
            capture("2-open-card-and-map")
            app.buttons["next-hole"].tap()
            XCTAssertTrue(app.staticTexts["Hole 2"].waitForExistence(timeout: 5), "Next hole did not move the map to hole 2")
            capture("3-open-next-hole")
        } else {
            // One pane at a time (closed iPhone Duo, regular iPhones): Card and Map tabs
            capture("2-closed-card")
            let tabBarMap = app.tabBars.buttons["Map"]
            let mapTab = tabBarMap.exists ? tabBarMap : app.buttons["Map"].firstMatch
            XCTAssertTrue(mapTab.waitForExistence(timeout: 5), "The Map tab is missing")
            mapTab.tap()
            XCTAssertTrue(mapPane.waitForExistence(timeout: 5), "The map did not appear")
            app.buttons["next-hole"].tap()
            XCTAssertTrue(app.staticTexts["Hole 2"].waitForExistence(timeout: 5), "Next hole did not move the map to hole 2")
            capture("3-closed-map")
        }

        // Turned sideways: every iPhone shows the card on the left and the hole on the right
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(2)
        let cardPane = app.otherElements["card-pane"]
        if cardPane.exists && mapPane.exists {
            // Frames may be reported upright or sideways, so compare along the screen's long side.
            let screen = app.frame
            let card = cardPane.frame, hole = mapPane.frame
            let cardFirst = screen.width > screen.height ? card.midX < hole.midX : card.midY < hole.midY
            XCTAssertTrue(cardFirst, "The card should be on the left and the hole on the right")
            XCTAssertTrue(app.staticTexts["nine-total-0"].isHittable, "The front nine total is cut off; the whole nine should fit on the card")
            XCTAssertTrue(app.buttons["score-0-9"].isHittable, "Hole 9 is cut off; the whole nine should fit on the card")
            capture("4-sideways-card-and-map")
        } else {
            // The closed Duo's outer screen may not turn sideways; any other iPhone must.
            XCTAssertTrue(Self.isDuo, "A sideways iPhone should show the card and the hole side by side")
            capture("4-sideways")
        }
    }

    /// The open iPhone Duo, drawn at its real size and shrunk to fit a sideways
    /// Pro Max, since the Duo simulator can't be unfolded here.
    @MainActor
    func testOpenDuoLayout() throws {
        let device = ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] ?? ""
        try XCTSkipUnless(device.contains("Pro Max"), "The open Duo picture is taken on the Pro Max only")
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-openDuoPreview"]
        app.launch()

        let cardPane = app.otherElements["card-pane"]
        let mapPane = app.otherElements["map-pane"]
        XCTAssertTrue(cardPane.waitForExistence(timeout: 15), "The card is missing from the open layout")
        XCTAssertTrue(mapPane.exists, "The hole is missing from the open layout")
        let screen = app.frame
        let card = cardPane.frame, hole = mapPane.frame
        let cardFirst = screen.width > screen.height ? card.midX < hole.midX : card.midY < hole.midY
        XCTAssertTrue(cardFirst, "The card should be on the left and the hole on the right")
        XCTAssertTrue(app.staticTexts["nine-total-0"].isHittable, "The front nine total is cut off")
        sleep(1)
        capture("5-open-duo-size-front")

        app.buttons["next-hole"].tap()
        XCTAssertTrue(app.staticTexts["Hole 2"].waitForExistence(timeout: 5), "Next hole did not move the map to hole 2")
        capture("6-open-duo-size-hole-2")
    }

    private static var isDuo: Bool {
        (ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] ?? "").contains("Duo")
    }

    @MainActor
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
