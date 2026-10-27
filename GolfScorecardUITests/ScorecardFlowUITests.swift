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
        let course = app.buttons["course-sample-links"]
        XCTAssertTrue(course.waitForExistence(timeout: 15), "The sample course is missing from the course list")
        capture("1-course-list")
        course.tap()

        // New round
        let start = app.buttons["start-round"]
        XCTAssertTrue(start.waitForExistence(timeout: 5), "The Start Round button is missing")
        start.tap()

        // Score hole 1: first tap jumps to par (4), second adds one
        let firstScore = app.buttons["score-0-1"]
        XCTAssertTrue(firstScore.waitForExistence(timeout: 5), "The score card did not appear")
        firstScore.tap()
        let plus = app.buttons["score-plus"]
        plus.tap()
        plus.tap()
        XCTAssertEqual(app.staticTexts["nine-total-0"].label, "5", "Front nine total should be 5 after scoring hole 1")
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

        // Turned sideways: large iPhones switch to card and map side by side
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(2)
        if app.otherElements["card-pane"].exists && mapPane.exists {
            capture("4-sideways-card-and-map")
        } else {
            capture("4-sideways")
        }
    }

    @MainActor
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
