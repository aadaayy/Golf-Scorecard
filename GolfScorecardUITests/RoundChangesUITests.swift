import XCTest

/// Deleting a round part way through, big scores on one line, the Profile
/// sections, and the round's Lock Screen card. Saves screenshots of each.
final class RoundChangesUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }

    /// Leaving in the middle of a round: Delete asks first, then the round is
    /// gone from home and from Past Rounds.
    @MainActor
    func testDeleteRoundMidGame() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-skipOnboarding", "-startLayout", "nine"]
        app.launch()

        startRound(in: app)
        app.buttons["score-0-1"].tap()
        let delete = app.buttons["delete-round"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5), "A round being played should have Delete")
        XCTAssertTrue(app.buttons["finish-round"].exists, "Finish should still be there beside Delete")
        capture("d1-round-with-delete")

        delete.tap()
        let confirm = app.buttons["Delete Round"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "Delete should ask first")
        sleep(1)
        capture("d2-delete-confirm")
        confirm.tap()

        XCTAssertTrue(app.buttons["course-pompano-pines"].waitForExistence(timeout: 5), "Deleting should go back home")
        sleep(1)
        XCTAssertFalse(app.buttons["resume-round"].exists, "A deleted round shouldn't be offered to resume")
        capture("d3-home-after-delete")
        tab("Past Rounds", in: app)
        XCTAssertFalse(app.buttons["past-round-0"].waitForExistence(timeout: 2), "A deleted round shouldn't be in Past Rounds")
    }

    /// Ten strokes or more stay on one line in the hole view, sideways and on
    /// the open Duo (drawn at its size on the Pro Max).
    @MainActor
    func testTenStrokesOnOneLine() throws {
        let app = XCUIApplication()
        if Self.device.contains("Pro Max") {
            XCUIDevice.shared.orientation = .landscapeLeft
            app.launchArguments = ["-uiTesting", "-skipOnboarding", "-openDuoPreview", "-startLayout", "hole"]
            app.launch()
            // The preview's round has 6 on hole 1 already.
            scoreTen(in: app, from: 6)
            capture("s1-open-duo-size-hole-10")
            app.terminate()
            XCUIDevice.shared.orientation = .portrait
        }

        app.launchArguments = ["-uiTesting", "-skipOnboarding", "-startLayout", "hole"]
        app.launch()
        startRound(in: app)
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(2)
        guard app.otherElements["hole-score-pane"].waitForExistence(timeout: 5) else {
            // The closed Duo's outer screen may not turn sideways; any other iPhone must.
            XCTAssertTrue(Self.device.contains("Duo"), "A sideways iPhone should show the hole view")
            return
        }
        scoreTen(in: app, from: 0)
        capture("s2-sideways-hole-10")
    }

    /// Profile & Settings: sections on the left and the picked one on the right
    /// when open or sideways; a list of pages when upright.
    @MainActor
    func testProfileSections() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-skipOnboarding", "-sampleRounds"]
        app.launch()
        XCTAssertTrue(app.buttons["resume-round"].waitForExistence(timeout: 15), "Home did not load")

        tab("Profile", in: app)
        let round = app.buttons["profile-section-round"]
        XCTAssertTrue(round.waitForExistence(timeout: 5), "Profile is missing During a Round")
        capture("p1-profile")
        round.tap()
        let lockScreen = app.switches["profile-lock-screen"]
        XCTAssertTrue(lockScreen.waitForExistence(timeout: 5), "During a Round is missing Show round on Lock Screen")
        XCTAssertEqual(lockScreen.value as? String, "1", "The Lock Screen card should start on")
        XCTAssertFalse(app.switches["Keep screen on"].exists, "Keep screen on should be gone from During a Round")
        capture("p2-during-a-round")
        back(in: app)
        app.buttons["profile-section-history"].tap()
        XCTAssertTrue(app.buttons["profile-past-rounds"].waitForExistence(timeout: 5), "History is missing See Past Rounds")
        capture("p3-history")
        back(in: app)

        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(2)
        if app.textFields["profile-name"].waitForExistence(timeout: 5) {
            capture("p4-sideways-profile")
            app.buttons["profile-section-round"].tap()
            XCTAssertTrue(app.switches["profile-lock-screen"].waitForExistence(timeout: 5), "Picking During a Round should show it beside the sections")
            capture("p5-sideways-profile-round")
        } else {
            XCTAssertTrue(Self.device.contains("Duo"), "Sideways, Profile should show My Profile beside the sections")
        }
        XCUIDevice.shared.orientation = .portrait

        guard Self.device.contains("Pro Max") else { return }
        app.terminate()
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launchArguments = ["-uiTesting", "-skipOnboarding", "-sampleRounds", "-openDuoPreview", "-home"]
        app.launch()
        XCTAssertTrue(app.otherElements["course-preview"].waitForExistence(timeout: 15), "The open Duo home did not load")
        tab("Profile", in: app)
        XCTAssertTrue(app.textFields["profile-name"].waitForExistence(timeout: 5), "Open, Profile should show My Profile beside the sections")
        sleep(1)
        capture("p6-open-duo-size-profile")
        for (section, name) in [("playing", "p7-open-duo-size-playing"), ("round", "p8-open-duo-size-round"),
                                ("history", "p9-open-duo-size-history"), ("about", "p10-open-duo-size-about")] {
            app.buttons["profile-section-\(section)"].tap()
            sleep(1)
            capture(name)
        }
    }

    /// The open Duo and a sideways phone each keep their own Hole or Nine pick.
    /// Both start on Hole; picking Nine for the open Duo on Profile leaves a
    /// sideways round on Hole, and the switch in a sideways round changes only
    /// the sideways pick.
    @MainActor
    func testSeparateOpenAndSidewaysViews() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-skipOnboarding"]
        app.launch()
        XCTAssertTrue(app.buttons["course-pompano-pines"].waitForExistence(timeout: 15), "Home did not load")

        tab("Profile", in: app)
        let playing = app.buttons["profile-section-playing"]
        XCTAssertTrue(playing.waitForExistence(timeout: 5), "Profile is missing Playing")
        playing.tap()
        let duoOpen = app.buttons["profile-layout-duoOpen"]
        let sideways = app.buttons["profile-layout-sideways"]
        XCTAssertTrue(duoOpen.waitForExistence(timeout: 5), "Playing is missing Duo open")
        XCTAssertTrue(sideways.exists, "Playing is missing Sideways")
        XCTAssertTrue(shows(duoOpen, "Hole"), "Duo open should start on Hole")
        XCTAssertTrue(shows(sideways, "Hole"), "Sideways should start on Hole")
        XCTAssertFalse(app.buttons["Open or sideways"].exists, "The old single setting should be gone")

        duoOpen.tap()
        let nine = app.buttons["Nine"].firstMatch
        XCTAssertTrue(nine.waitForExistence(timeout: 5), "Duo open should offer Nine")
        nine.tap()
        sleep(1)
        XCTAssertTrue(shows(duoOpen, "Nine"), "Duo open should now be Nine")
        XCTAssertTrue(shows(sideways, "Hole"), "Picking for Duo open shouldn't change Sideways")
        capture("v1-profile-playing")
        back(in: app)

        // A sideways round starts on its own pick, Hole.
        tab("Play", in: app)
        startRound(in: app)
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(2)
        if app.otherElements["hole-score-pane"].waitForExistence(timeout: 5) {
            XCTAssertFalse(app.otherElements["nine-pane"].exists, "Sideways should show the hole view, not Duo open's nine view")
            capture("v3-sideways-round-hole")

            // Switching in the round changes the sideways pick.
            app.buttons["Nine"].firstMatch.tap()
            XCTAssertTrue(app.otherElements["nine-pane"].waitForExistence(timeout: 5), "Nine in the round should show the nine view")
            sleep(1)
            capture("v4-sideways-round-switched-nine")
        } else {
            // The closed Duo's outer screen may not turn sideways; any other iPhone must.
            XCTAssertTrue(Self.device.contains("Duo"), "A sideways round should start on the hole view")
        }
        XCUIDevice.shared.orientation = .portrait

        // The open Duo, drawn at its size on the Pro Max: Profile and a round
        // with Duo open on Nine and Sideways on Hole.
        guard Self.device.contains("Pro Max") else { return }
        app.terminate()
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launchArguments = ["-uiTesting", "-skipOnboarding", "-openDuoPreview", "-home",
                               "-startDuoOpen", "nine", "-startSideways", "hole"]
        app.launch()
        XCTAssertTrue(app.otherElements["course-preview"].waitForExistence(timeout: 15), "The open Duo home did not load")
        tab("Profile", in: app)
        app.buttons["profile-section-playing"].tap()
        XCTAssertTrue(app.buttons["profile-layout-sideways"].waitForExistence(timeout: 5), "Open, Playing should show both settings")
        sleep(1)
        capture("v2-open-duo-size-playing")

        app.terminate()
        app.launchArguments = ["-uiTesting", "-skipOnboarding", "-openDuoPreview",
                               "-startDuoOpen", "nine", "-startSideways", "hole"]
        app.launch()
        XCTAssertTrue(app.otherElements["nine-pane"].waitForExistence(timeout: 15), "The open Duo should start on its own pick, Nine")
        XCTAssertFalse(app.otherElements["hole-score-pane"].exists, "The open Duo shouldn't follow Sideways")
        sleep(1)
        capture("v5-open-duo-size-round-nine")

        // Someone who picked Nine before the split keeps Nine on both.
        app.terminate()
        app.launchArguments = ["-uiTesting", "-skipOnboarding", "-openDuoPreview", "-oldLayout", "nine"]
        app.launch()
        XCTAssertTrue(app.otherElements["nine-pane"].waitForExistence(timeout: 15), "An old Nine pick should carry over to the open Duo")
    }

    /// A Profile picker row shows its pick in its label or its value.
    private func shows(_ row: XCUIElement, _ pick: String) -> Bool {
        row.label.contains(pick) || (row.value as? String)?.contains(pick) == true
    }

    /// The round's card on the Lock Screen: first drawn inside the app, then,
    /// where the simulator allows, the real one from a round being played.
    @MainActor
    func testLockScreenCard() throws {
        let preview = XCUIApplication()
        preview.launchArguments = ["-uiTesting", "-skipOnboarding", "-lockScreenPreview"]
        preview.launch()
        XCTAssertTrue(preview.staticTexts["Hole 9"].waitForExistence(timeout: 15), "The Lock Screen card preview is missing")
        XCTAssertFalse(preview.buttons["Keep screen on"].exists, "The card should no longer have Keep screen on")
        sleep(1)
        capture("l1-lock-screen-card-preview")
        preview.terminate()
        preview.launchArguments.append("-alwaysOn")
        preview.launch()
        XCTAssertTrue(preview.staticTexts["Hole 9"].waitForExistence(timeout: 15), "The Always-On card preview is missing")
        sleep(1)
        capture("l1b-lock-screen-card-always-on")
        preview.terminate()

        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-skipOnboarding", "-startLayout", "nine"]
        app.launch()
        startRound(in: app)
        app.buttons["score-0-1"].tap()
        sleep(2)

        // Leave the app and pull down the Lock Screen (Notification Center).
        XCUIDevice.shared.press(.home)
        sleep(2)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.002))
            .press(forDuration: 0.1, thenDragTo: springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.75)))
        sleep(3)
        // The first card asks whether to allow Live Activities from Scorecard.
        let allow = springboard.buttons["Allow"]
        if allow.waitForExistence(timeout: 3) {
            allow.tap()
            sleep(2)
        }
        capture("l2-lock-screen")
        let card = springboard.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Hole 1'")).firstMatch
        if card.waitForExistence(timeout: 5) {
            // Tapping the card opens the round at that hole.
            card.tap()
            XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10), "Tapping the card should open the app")
            XCTAssertTrue(app.buttons["finish-round"].waitForExistence(timeout: 5), "Tapping the card should open the round")
            capture("l3-opened-from-lock-screen")
        } else {
            // Not every simulator shows Live Activities here; the preview above still shows the card.
            let note = XCTAttachment(string: "The Lock Screen card wasn't found on this simulator.")
            note.name = "l2-note"
            note.lifetime = .keepAlways
            add(note)
        }
    }

    // MARK: - Helpers

    private func startRound(in app: XCUIApplication) {
        let course = app.buttons["course-pompano-pines"]
        XCTAssertTrue(course.waitForExistence(timeout: 15), "Pompano Beach Pines is missing from the course list")
        course.tap()
        let start = app.buttons["start-round"]
        XCTAssertTrue(start.waitForExistence(timeout: 5), "The Start Round button is missing")
        start.tap()
        XCTAssertTrue(app.buttons["finish-round"].waitForExistence(timeout: 5), "The round did not open")
    }

    /// Taps + until hole 1 shows 10, then checks the 10 sits on one line.
    private func scoreTen(in app: XCUIApplication, from start: Int) {
        let plus = app.buttons["hole-score-plus-0"]
        XCTAssertTrue(plus.waitForExistence(timeout: 15), "The hole view's + is missing")
        // From nothing, the first tap scores par (5 on hole 1).
        var strokes = start
        while strokes < 10 {
            plus.tap()
            strokes = strokes == 0 ? 5 : strokes + 1
        }
        let value = app.staticTexts["hole-score-value-0"]
        XCTAssertEqual(value.label, "10", "Hole 1 should show 10 strokes")
        // Upright, a frame taller than wide means the digits wrapped onto two lines.
        // Frames may come back turned with the phone, so compare the long and short sides.
        let frame = value.frame
        let screen = app.frame
        let across = screen.width > screen.height ? frame.width : frame.height
        let down = screen.width > screen.height ? frame.height : frame.width
        XCTAssertGreaterThan(across, down * 0.8, "10 should read across on one line, not stack 1 above 0")
        sleep(1)
    }

    /// The app's tabs sit in a tab bar on most iPhones and at the side on the Duo.
    private func tab(_ name: String, in app: XCUIApplication) {
        let inBar = app.tabBars.buttons[name]
        let button = inBar.waitForExistence(timeout: 3) ? inBar : app.buttons[name].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 5), "The \(name) tab is missing")
        button.tap()
        sleep(1)
    }

    /// The Back button is in the navigation bar on most iPhones and at the side on the Duo.
    private func back(in app: XCUIApplication) {
        let side = app.buttons["BackButton"].firstMatch
        let button = side.exists ? side : app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(button.waitForExistence(timeout: 5), "Back is missing")
        button.tap()
        sleep(1)
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
