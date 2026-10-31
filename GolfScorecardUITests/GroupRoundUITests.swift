import XCTest

/// Group rounds against the pretend server (-mockGroup), since the checks have
/// no Supabase project or Google account: starting one and seeing friends join
/// and score, joining with a code, the account in Profile, the open Duo, and
/// what shows before the app is set up. Saves g* screenshots.
final class GroupRoundUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }

    /// Start Group Round asks to sign in, then the round opens with its code;
    /// Sam and Jordan join, and their scores fill in after yours. A friend's row
    /// has no buttons: they enter their own.
    @MainActor
    func testStartGroupRound() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-skipOnboarding", "-mockGroup", "-startLayout", "nine"]
        app.launch()

        let course = app.buttons["course-pompano-pines"]
        XCTAssertTrue(course.waitForExistence(timeout: 15), "Pompano Beach Pines is missing from the course list")
        course.tap()
        let startGroup = app.buttons["start-group-round"]
        XCTAssertTrue(startGroup.waitForExistence(timeout: 5), "Start Group Round is missing")
        reveal(startGroup, in: app)
        capture("g1-new-round")
        startGroup.tap()

        let google = app.buttons["sign-in-google"]
        XCTAssertTrue(google.waitForExistence(timeout: 5), "Starting a group round signed out should ask to sign in")
        XCTAssertFalse(app.buttons["sign-in-apple"].exists, "Sign in with Apple stays off until it's turned on")
        sleep(1)
        capture("g2-sign-in")
        google.tap()

        XCTAssertTrue(app.buttons["finish-round"].waitForExistence(timeout: 10), "The group round did not open after signing in")
        let code = app.staticTexts["group-code"]
        XCTAssertTrue(code.waitForExistence(timeout: 5), "The round should show its join code")
        XCTAssertEqual(code.label, "Code P N S 2 3 4")
        XCTAssertTrue(app.buttons["group-invite"].exists, "Invite should be beside the code")

        // Friends join on their own.
        XCTAssertTrue(app.buttons["score-2-1"].waitForExistence(timeout: 10), "Sam and Jordan should get rows as they join")
        XCTAssertEqual(app.staticTexts["group-status"].label, "Live")

        // Your score goes out, and theirs come back.
        app.buttons["score-0-1"].tap()
        app.buttons["score-plus"].tap()
        XCTAssertEqual(app.staticTexts["score-value"].label, "5", "The first tap scores par")
        let sam = app.buttons["score-1-1"]
        XCTAssertTrue(waitFor(sam, value: "6"), "Sam's score should show up on your card")
        XCTAssertTrue(waitFor(app.buttons["score-2-1"], value: "5"), "Jordan's score should show up on your card")
        app.buttons["score-0-2"].tap()
        app.buttons["score-plus"].tap()
        app.buttons["score-plus"].tap()
        XCTAssertTrue(waitFor(app.buttons["score-1-2"], value: "6"), "Each hole you score, they score too")
        capture("g3-group-round-live")

        sam.tap()
        XCTAssertTrue(app.otherElements["friend-score-bar"].waitForExistence(timeout: 5), "A friend's row should say they enter their own score")
        XCTAssertFalse(app.buttons["score-plus"].exists, "A friend's score can't be changed from your phone")
        capture("g4-friends-row")

        if !Self.device.contains("Duo") {
            XCUIDevice.shared.orientation = .landscapeLeft
            sleep(2)
            XCTAssertTrue(app.otherElements["group-bar"].waitForExistence(timeout: 5), "Sideways, the code should still show")
            capture("g5-sideways-group-nine")
            app.buttons["Hole"].firstMatch.tap()
            sleep(1)
            XCTAssertTrue(app.otherElements["hole-score-pane"].waitForExistence(timeout: 5), "The hole view should show")
            let friendPlus = app.buttons["hole-score-plus-1"]
            XCTAssertFalse(friendPlus.exists && friendPlus.isHittable, "A friend's row in the hole view has no buttons")
            capture("g6-sideways-group-hole")
            XCUIDevice.shared.orientation = .portrait
            sleep(1)
        }

        app.buttons["finish-round"].tap()
        let save = app.buttons["save-round"]
        XCTAssertTrue(save.waitForExistence(timeout: 5), "Finish should show the summary")
        capture("g7-group-summary")
        save.tap()
        XCTAssertTrue(app.buttons["course-pompano-pines"].waitForExistence(timeout: 5), "Saving should go back home")
    }

    /// Join a Group Round on Play: sign in, a wrong code says so, and the right
    /// one opens Sam's round with everyone's scores so far, on your own row.
    @MainActor
    func testJoinGroupRound() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-skipOnboarding", "-mockGroup", "-startLayout", "nine"]
        app.launch()

        let join = app.buttons["join-group-round"]
        XCTAssertTrue(join.waitForExistence(timeout: 15), "Play should have Join a Group Round")
        reveal(join, in: app)
        capture("g8-home-join")
        join.tap()

        let google = app.buttons["sign-in-google"]
        XCTAssertTrue(google.waitForExistence(timeout: 5), "Joining signed out should ask to sign in first")
        capture("g9-join-sign-in")
        google.tap()

        let field = app.textFields["join-code"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "After signing in, the code box should show")
        field.tap()
        field.typeText("zzz999")
        app.buttons["join-submit"].tap()
        let problem = app.staticTexts["join-problem"]
        XCTAssertTrue(problem.waitForExistence(timeout: 5), "A wrong code should say so")
        capture("g10-join-wrong-code")

        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 10))
        field.typeText("green4")
        capture("g11-join-code")
        app.buttons["join-submit"].tap()

        XCTAssertTrue(app.buttons["finish-round"].waitForExistence(timeout: 10), "The joined round did not open")
        XCTAssertTrue(waitFor(app.buttons["score-0-1"], value: "6"), "Sam's scores so far should be on the card")
        XCTAssertTrue(waitFor(app.buttons["score-1-3"], value: "4"), "Jordan's scores so far should be on the card")
        // You're third on the card, and the buttons are for your row.
        XCTAssertTrue(app.buttons["score-2-3"].exists, "You should have a row")
        let plus = app.buttons["score-plus"]
        XCTAssertTrue(plus.waitForExistence(timeout: 5), "Your own row should have the score buttons")
        plus.tap()
        XCTAssertTrue(waitFor(app.buttons["score-2-3"], value: "3"), "Your score goes on your row (par 3)")
        capture("g12-joined-round")
    }

    /// Profile's account: who's signed in, Sign Out, and Delete Account.
    @MainActor
    func testGroupAccountInProfile() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-skipOnboarding", "-mockGroup", "-mockSignedIn"]
        app.launch()
        XCTAssertTrue(app.buttons["course-pompano-pines"].waitForExistence(timeout: 15), "Home did not load")
        tab("Profile", in: app)
        let myProfile = app.buttons["profile-section-profile"]
        XCTAssertTrue(myProfile.waitForExistence(timeout: 5), "Profile is missing My Profile")
        myProfile.tap()
        XCTAssertTrue(app.textFields["profile-name"].waitForExistence(timeout: 5), "My Profile did not open")
        app.swipeUp()

        let name = app.staticTexts["account-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5), "My Profile should show who's signed in")
        XCTAssertEqual(name.label, "Alex Rivera")
        XCTAssertTrue(app.buttons["account-delete"].exists, "Delete Account should be there for signed-in players")
        capture("g13-profile-account")

        app.buttons["account-sign-out"].tap()
        XCTAssertTrue(app.buttons["sign-in-google"].waitForExistence(timeout: 5), "After signing out, Continue with Google should show")
        capture("g14-profile-signed-out")
    }

    /// The open Duo (drawn at its size on the Pro Max): a joined group round
    /// in the nine view and the hole view.
    @MainActor
    func testOpenDuoGroupRound() throws {
        guard Self.device.contains("Pro Max") else { return }
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-skipOnboarding", "-mockGroup", "-mockSignedIn",
                               "-openDuoPreview", "-groupRound", "-startLayout", "nine"]
        app.launch()
        XCTAssertTrue(app.otherElements["group-bar"].waitForExistence(timeout: 15), "The open Duo group round did not load")
        XCTAssertTrue(waitFor(app.buttons["score-0-1"], value: "6"), "Sam's scores should be on the open card")
        sleep(1)
        capture("g15-open-duo-size-group-nine")
        app.buttons["Hole"].firstMatch.tap()
        XCTAssertTrue(app.otherElements["hole-score-pane"].waitForExistence(timeout: 5), "The hole view should show")
        sleep(1)
        capture("g16-open-duo-size-group-hole")
    }

    /// Before GroupScoring.plist is filled in, Start Group Round says so and
    /// nothing else changes.
    @MainActor
    func testNotSetUpYet() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-skipOnboarding"]
        app.launch()
        let course = app.buttons["course-pompano-pines"]
        XCTAssertTrue(course.waitForExistence(timeout: 15), "Pompano Beach Pines is missing from the course list")
        course.tap()
        let startGroup = app.buttons["start-group-round"]
        XCTAssertTrue(startGroup.waitForExistence(timeout: 5), "Start Group Round is missing")
        reveal(startGroup, in: app)
        startGroup.tap()
        XCTAssertTrue(app.alerts["Group rounds aren't set up yet"].waitForExistence(timeout: 5), "Without a project it should say group rounds aren't set up")
        capture("g17-not-set-up")
    }

    // MARK: - Helpers

    /// Scrolls up until the element can be tapped, for the smaller phones.
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        var tries = 0
        while !element.isHittable && tries < 4 {
            app.swipeUp()
            tries += 1
        }
    }

    private func waitFor(_ element: XCUIElement, value: String, timeout: TimeInterval = 10) -> Bool {
        let predicate = NSPredicate(format: "value == %@", value)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    /// The app's tabs sit in a tab bar on most iPhones and at the side on the Duo.
    private func tab(_ name: String, in app: XCUIApplication) {
        let inBar = app.tabBars.buttons[name]
        let button = inBar.waitForExistence(timeout: 3) ? inBar : app.buttons[name].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 5), "The \(name) tab is missing")
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
