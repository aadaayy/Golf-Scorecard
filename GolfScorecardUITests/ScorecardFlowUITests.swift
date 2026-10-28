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
        app.launchArguments = ["-uiTesting", "-skipOnboarding", "-startLayout", "nine"]
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
        if app.otherElements["nine-pane"].exists {
            // Wide layout from the start (open iPhone Duo): the card and the nine holes side by side
            capture("2-open-card-and-nine")
            app.buttons["nine-hole-2"].tap()
            capture("3-open-hole-2")
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

        // Turned sideways: every iPhone shows two halves, starting with the nine view
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(2)
        let cardPane = app.otherElements["card-pane"]
        let ninePane = app.otherElements["nine-pane"]
        if cardPane.exists && ninePane.exists {
            XCTAssertTrue(isLeft(cardPane, of: ninePane, in: app), "The card should be on the left and the nine holes on the right")
            XCTAssertTrue(app.staticTexts["nine-total-0"].isHittable, "The front nine total is cut off; the whole nine should fit on the card")
            XCTAssertTrue(app.buttons["score-0-9"].isHittable, "Hole 9 is cut off; the whole nine should fit on the card")
            app.buttons["nine-hole-3"].tap()
            capture("4-sideways-card-and-map")

            // The hole view: the score for hole 3 on the left, hole 3 on the right
            app.buttons["Hole"].tap()
            let scorePane = app.otherElements["hole-score-pane"]
            XCTAssertTrue(scorePane.waitForExistence(timeout: 5), "The hole view's score is missing")
            XCTAssertTrue(mapPane.exists, "The hole view's map is missing")
            XCTAssertTrue(isLeft(scorePane, of: mapPane, in: app), "The score should be on the left and the hole on the right")
            XCTAssertTrue(app.staticTexts["Hole 3"].exists, "Tapping hole 3 in the nine view should open hole 3")
            app.buttons["hole-score-plus-0"].tap()
            XCTAssertEqual(app.staticTexts["hole-score-value-0"].label, "3", "The first tap should score par on the par 3")
            capture("5-sideways-hole-view")

            // Pinch to zoom the hole, then double tap to zoom back out. Where the
            // yardages fit beside the hole, they make room while zoomed in.
            let drawing = app.otherElements["hole-drawing"]
            let map = drawing.images["Map of hole 3"]
            let yardages = app.otherElements["tee-yardages"]
            let hadYardages = yardages.exists
            XCTAssertEqual(map.value as? String, "Zoomed out", "The hole should start zoomed out")
            drawing.pinch(withScale: 3, velocity: 2)
            sleep(1)
            XCTAssertEqual(map.value as? String, "Zoomed in", "Pinching should zoom in on the hole")
            if hadYardages {
                XCTAssertFalse(yardages.exists, "Zooming in should give the drawing the yardages' room")
            }
            capture("5b-sideways-hole-view-zoomed")
            drawing.doubleTap()
            sleep(1)
            XCTAssertEqual(map.value as? String, "Zoomed out", "A double tap should zoom back out")
            if hadYardages {
                XCTAssertTrue(yardages.exists, "The yardages should come back after zooming out")
            }
        } else {
            // The closed Duo's outer screen may not turn sideways; any other iPhone must.
            XCTAssertTrue(Self.isDuo, "A sideways iPhone should show two halves")
            capture("4-sideways")
        }
    }

    /// The open iPhone Duo, drawn at its real size and shrunk to fit a sideways
    /// Pro Max, since the Duo simulator can't be unfolded here. Both layouts.
    @MainActor
    func testOpenDuoLayouts() throws {
        let device = ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] ?? ""
        try XCTSkipUnless(device.contains("Pro Max"), "The open Duo pictures are taken on the Pro Max only")
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-skipOnboarding", "-openDuoPreview", "-startLayout", "nine"]
        app.launch()

        let cardPane = app.otherElements["card-pane"]
        let ninePane = app.otherElements["nine-pane"]
        XCTAssertTrue(cardPane.waitForExistence(timeout: 15), "The nine view's card is missing")
        XCTAssertTrue(ninePane.exists, "The nine view's holes are missing")
        XCTAssertTrue(isLeft(cardPane, of: ninePane, in: app), "The card should be on the left and the nine holes on the right")
        sleep(1)
        capture("6-open-duo-size-nine-view")

        app.buttons["Back 9"].tap()
        XCTAssertTrue(app.buttons["nine-hole-14"].waitForExistence(timeout: 5), "The back nine's holes did not appear")
        capture("7-open-duo-size-nine-view-back")

        app.buttons["Hole"].tap()
        let scorePane = app.otherElements["hole-score-pane"]
        XCTAssertTrue(scorePane.waitForExistence(timeout: 5), "The hole view's score is missing")
        XCTAssertTrue(app.otherElements["map-pane"].exists, "The hole view's map is missing")
        app.buttons["hole-score-plus-0"].tap()
        sleep(1)
        capture("8-open-duo-size-hole-view")

        app.otherElements["hole-drawing"].pinch(withScale: 3, velocity: 2)
        sleep(1)
        capture("9-open-duo-size-hole-zoomed")
    }

    /// Whether `first` comes before `second` along the screen's long side.
    /// Frames may be reported upright or sideways, so this checks both ways.
    private func isLeft(_ first: XCUIElement, of second: XCUIElement, in app: XCUIApplication) -> Bool {
        let screen = app.frame
        let a = first.frame, b = second.frame
        return screen.width > screen.height ? a.midX < b.midX : a.midY < b.midY
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
