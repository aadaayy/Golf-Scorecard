import XCTest

/// Everything outside a round: the welcome pages, home, past rounds, the
/// end-of-round summary and profile. Saves screenshots of each.
final class OutsideRoundUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }

    /// The first launch: three pages, then home greets you by name.
    @MainActor
    func testWelcomePages() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()

        let next = app.buttons["onboarding-next"]
        XCTAssertTrue(next.waitForExistence(timeout: 15), "The welcome page did not show on first launch")
        XCTAssertTrue(app.buttons["onboarding-skip"].exists, "Skip is missing")
        capture("o1-welcome")
        next.tap()

        let name = app.textFields["onboarding-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5), "The name field is missing")
        name.tap()
        name.typeText("Alberto")
        let handicap = app.textFields["onboarding-handicap"]
        handicap.tap()
        handicap.typeText("14.2")
        capture("o2-whos-playing")
        app.buttons["onboarding-next"].tap()

        let hole = app.buttons["onboarding-layout-hole"]
        XCTAssertTrue(hole.waitForExistence(timeout: 5), "The open view choice is missing")
        hole.tap()
        capture("o3-open-view")
        app.buttons["onboarding-done"].tap()

        XCTAssertTrue(app.navigationBars["Hi, Alberto"].waitForExistence(timeout: 5), "Home should greet the golfer by name")
        capture("o4-home-first-time")

        // The name is already on the card as the first player.
        app.buttons["course-pompano-pines"].tap()
        let firstPlayer = app.textFields["player-0"]
        XCTAssertTrue(firstPlayer.waitForExistence(timeout: 5), "The start round screen is missing")
        XCTAssertEqual(firstPlayer.value as? String, "Alberto", "The golfer should already be player 1")
        capture("o5-start-round")
    }

    /// Home with a round to pick up, past rounds, a finished card, its summary,
    /// profile, finishing a round, and erasing everything.
    @MainActor
    func testHomePastRoundsAndProfile() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-skipOnboarding", "-sampleRounds", "-startLayout", "nine"]
        app.launch()

        let resume = app.buttons["resume-round"]
        XCTAssertTrue(resume.waitForExistence(timeout: 15), "Home should offer to resume today's round")
        capture("h1-home")

        // Past rounds, newest first: today's unfinished round, a nine, a full round.
        tab("Past Rounds", in: app)
        let fullRound = app.buttons["past-round-2"]
        XCTAssertTrue(fullRound.waitForExistence(timeout: 5), "The sample rounds are missing from Past Rounds")
        capture("h2-past-rounds")
        fullRound.tap()

        // A finished round is locked until Edit.
        let edit = app.buttons["edit-round"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5), "A finished round should have Edit")
        XCTAssertFalse(app.buttons["score-plus"].exists, "A finished round's scores shouldn't change without Edit")
        capture("h3-finished-card")
        edit.tap()
        XCTAssertTrue(app.buttons["score-plus"].waitForExistence(timeout: 5), "Edit should bring back the score buttons")
        edit.tap()

        app.buttons["show-summary"].tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5), "The summary did not open")
        XCTAssertTrue(app.descendants(matching: .any)["summary-net"].exists,
                      "A full round with a handicap should show the net score")
        capture("h4-summary")
        app.buttons["Done"].tap()
        goBack(app)

        // Profile
        tab("Profile", in: app)
        XCTAssertTrue(app.buttons["erase-everything"].waitForExistence(timeout: 5), "Profile is missing Erase Everything")
        capture("h5-profile")
        tab("Play", in: app)

        // Pick today's round back up and finish it.
        XCTAssertTrue(resume.waitForExistence(timeout: 5))
        resume.tap()
        let finish = app.buttons["finish-round"]
        XCTAssertTrue(finish.waitForExistence(timeout: 5), "A round being played should have Finish")
        capture("h6-resumed-round")
        finish.tap()
        let save = app.buttons["save-round"]
        XCTAssertTrue(save.waitForExistence(timeout: 5), "The finish summary is missing")
        capture("h7-finish-summary")
        save.tap()
        XCTAssertTrue(app.buttons["course-pompano-pines"].waitForExistence(timeout: 5), "Saving should go back home")
        XCTAssertFalse(app.buttons["resume-round"].exists, "Nothing should be left to resume")

        // Sideways (and on the open Duo): courses on the left, the course on the right.
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(2)
        if app.otherElements["course-preview"].waitForExistence(timeout: 5) {
            XCTAssertTrue(app.buttons["play-course"].exists, "The course preview should have Play")
            capture("h8-sideways-home")

            // Past rounds: the list on the left, the picked round on the right.
            tab("Past Rounds", in: app)
            XCTAssertTrue(app.otherElements["round-detail"].waitForExistence(timeout: 5), "Sideways, the picked round should show beside the list")
            app.buttons["past-round-1"].tap()
            XCTAssertTrue(app.buttons["open-round"].waitForExistence(timeout: 5), "The picked round should have Open Card")
            capture("h10-sideways-past-rounds")

            tab("Profile", in: app)
            XCTAssertTrue(app.buttons["erase-everything"].waitForExistence(timeout: 5), "Profile is missing Erase Everything")
            capture("h11-sideways-profile")
        } else {
            XCTAssertTrue(Self.isDuo, "A sideways iPhone should show the course beside the list")
        }
        XCUIDevice.shared.orientation = .portrait
        sleep(1)

        // Erase everything: the welcome pages come back.
        tab("Profile", in: app)
        let erase = app.buttons["erase-everything"]
        XCTAssertTrue(erase.waitForExistence(timeout: 5))
        erase.tap()
        let confirm = app.buttons.matching(NSPredicate(format: "label == 'Erase Everything' AND identifier != 'erase-everything'")).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "Erase should ask first")
        confirm.tap()
        XCTAssertTrue(app.buttons["onboarding-next"].waitForExistence(timeout: 5), "After erasing, the welcome pages should show again")
    }

    /// Home at the open iPhone Duo's size, drawn on the Pro Max (see OpenDuoPreview).
    @MainActor
    func testOpenDuoHome() throws {
        let device = ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] ?? ""
        try XCTSkipUnless(device.contains("Pro Max"), "The open Duo pictures are taken on the Pro Max only")
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-skipOnboarding", "-sampleRounds", "-openDuoPreview", "-home"]
        app.launch()
        XCTAssertTrue(app.otherElements["course-preview"].waitForExistence(timeout: 15), "The open Duo home should show the course beside the list")
        sleep(1)
        capture("h9-open-duo-size-home")

        tab("Past Rounds", in: app)
        XCTAssertTrue(app.otherElements["round-detail"].waitForExistence(timeout: 5), "The picked round should show beside the list")
        sleep(1)
        capture("h12-open-duo-size-past-rounds")

        tab("Profile", in: app)
        XCTAssertTrue(app.buttons["erase-everything"].waitForExistence(timeout: 5), "Profile is missing Erase Everything")
        sleep(1)
        capture("h13-open-duo-size-profile")
    }

    /// The app's tabs sit in a tab bar on most iPhones and at the side on the Duo.
    private func tab(_ name: String, in app: XCUIApplication) {
        let inBar = app.tabBars.buttons[name]
        let button = inBar.waitForExistence(timeout: 3) ? inBar : app.buttons[name].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 5), "The \(name) tab is missing")
        button.tap()
        sleep(1)
    }

    private func goBack(_ app: XCUIApplication) {
        // Look for Back by name: the iPhone Duo puts it at the side of the
        // screen, outside the nav bar, whose first button is then a toolbar button.
        let named = app.buttons["BackButton"].firstMatch
        let back = named.waitForExistence(timeout: 5) ? named : app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(back.exists, "There's no Back button")
        back.tap()
        sleep(1)
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
