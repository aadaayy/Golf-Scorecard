import XCTest

/// Group rounds against the pretend server (-mockGroup), since the checks have
/// no Supabase project or Google account: starting one and seeing friends join
/// and score, joining with a code, the account in Profile, the open Duo, and
/// what shows before the app is set up, and the account screen (Google or
/// email) that covers the app until someone is signed in. Saves g* and e* screenshots.
final class GroupRoundUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }

    /// Start Group Round (already signed in: the app asks for an account
    /// before anything else) opens the round with its code; Sam and Jordan join, and their scores fill in after yours. A friend's row
    /// has no buttons: they enter their own.
    @MainActor
    func testStartGroupRound() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-skipOnboarding", "-mockGroup", "-mockSignedIn", "-startLayout", "nine"]
        app.launch()

        let course = app.buttons["course-pompano-pines"]
        XCTAssertTrue(course.waitForExistence(timeout: 15), "Pompano Beach Pines is missing from the course list")
        course.tap()
        let startGroup = app.buttons["start-group-round"]
        XCTAssertTrue(startGroup.waitForExistence(timeout: 5), "Start Group Round is missing")
        reveal(startGroup, in: app)
        capture("g1-new-round")
        startGroup.tap()

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

    /// Join a Group Round on Play (signed in): a wrong code says so, and the right
    /// one opens Sam's round with everyone's scores so far, on your own row.
    @MainActor
    func testJoinGroupRound() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-skipOnboarding", "-mockGroup", "-mockSignedIn", "-startLayout", "nine"]
        app.launch()

        let join = app.buttons["join-group-round"]
        XCTAssertTrue(join.waitForExistence(timeout: 15), "Play should have Join a Group Round")
        reveal(join, in: app)
        capture("g8-home-join")
        join.tap()

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
        XCTAssertTrue(app.buttons["sign-in-google"].waitForExistence(timeout: 5), "After signing out, the account screen should come back")
        XCTAssertTrue(app.buttons["sign-in-email"].exists, "The account screen should offer email too")
        let signOut = app.buttons["account-sign-out"]
        XCTAssertFalse(signOut.exists && signOut.isHittable, "The account screen should cover Profile")
        capture("g14-signed-out-account-screen")
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

    /// Signed out, the app opens on the account screen: Google or email.
    /// Create Account (where the email opens) asks to check the email; Sign
    /// In says when the password is wrong, Forgot Password says a link is on
    /// its way, and the right password opens the app.
    @MainActor
    func testAccountScreenWithEmail() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-skipOnboarding", "-mockGroup", "-startLayout", "nine"]
        app.launch()

        let emailButton = app.buttons["sign-in-email"]
        XCTAssertTrue(emailButton.waitForExistence(timeout: 15), "Signed out, the app should open on the account screen")
        XCTAssertTrue(app.buttons["sign-in-google"].exists, "Continue with Google should be on the account screen")
        XCTAssertFalse(app.buttons["sign-in-apple"].exists, "Sign in with Apple stays off until it's turned on")
        let hidden = app.buttons["course-pompano-pines"]
        XCTAssertFalse(hidden.exists && hidden.isHittable, "Nothing else should be usable before signing in")
        sleep(1)
        capture("e1-account-screen")
        emailButton.tap()

        let address = app.textFields["email-address"]
        XCTAssertTrue(address.waitForExistence(timeout: 5), "The email form did not open")
        let submit = app.buttons["email-submit"]
        XCTAssertEqual(submit.label, "Create Account", "On the account screen, email starts on Create Account")
        address.tap()
        address.typeText("sam@example.com")
        let password = app.secureTextFields["email-password"]
        password.tap()
        password.typeText("birdie99")
        sleep(1)
        capture("e2-email-create-account")
        submit.tap()
        XCTAssertTrue(app.otherElements["email-check"].waitForExistence(timeout: 5), "A new account should ask to check the email")
        XCTAssertTrue(app.buttons["email-resend"].exists, "Resend Email should be there")
        capture("e3-email-check-inbox")

        // Sign In instead, with a wrong password.
        app.buttons["email-different"].tap()
        app.segmentedControls["email-mode"].buttons["Sign In"].tap()
        XCTAssertTrue(address.waitForExistence(timeout: 5), "The email form should come back")
        address.tap()
        address.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 30))
        address.typeText("alex@example.com")
        password.tap()
        password.typeText("nope1234")
        sleep(1)
        capture("e4-email-sign-in")
        app.buttons["email-submit"].tap()
        XCTAssertTrue(app.staticTexts["email-problem"].waitForExistence(timeout: 5), "A wrong password should say so")
        capture("e5-email-wrong-password")

        app.buttons["email-forgot"].tap()
        XCTAssertTrue(app.staticTexts["email-note"].waitForExistence(timeout: 5), "Forgot Password should say a link is on its way")
        capture("e6-email-forgot-password")

        // The right password: the account screen goes and the app opens.
        password.tap()
        password.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 20))
        password.typeText("golf1234")
        app.buttons["email-submit"].tap()
        let course = app.buttons["course-pompano-pines"]
        XCTAssertTrue(course.waitForExistence(timeout: 10), "Signing in should open the app")
        XCTAssertTrue(waitForHittable(course), "The account screen should be gone after signing in")
        capture("e7-signed-in-home")
    }

    /// The very first launch: the account first (Google here), then the
    /// welcome pages, with the name filled in from the account.
    @MainActor
    func testFirstLaunchAsksForAccount() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-mockGroup"]
        app.launch()

        let google = app.buttons["sign-in-google"]
        XCTAssertTrue(google.waitForExistence(timeout: 15), "The first launch should start on the account screen")
        XCTAssertFalse(app.buttons["onboarding-skip"].exists, "There's no skipping the account")
        google.tap()

        let next = app.buttons["onboarding-next"]
        XCTAssertTrue(next.waitForExistence(timeout: 10), "After the account, the welcome pages should show")
        capture("e8-first-launch-welcome")
        next.tap()
        let name = app.textFields["onboarding-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5), "Who's playing should show")
        XCTAssertEqual(name.value as? String, "Alex Rivera", "The name should come from the account")
        capture("e9-first-launch-name")
    }

    /// A reset link, opened from the account screen, asks for the new
    /// password, then opens the app signed in.
    @MainActor
    func testResetPasswordLink() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-skipOnboarding", "-mockGroup"]
        app.launch()
        let emailButton = app.buttons["sign-in-email"]
        XCTAssertTrue(emailButton.waitForExistence(timeout: 15), "Signed out, the app should open on the account screen")
        emailButton.tap()
        app.segmentedControls["email-mode"].buttons["Sign In"].tap()

        let address = app.textFields["email-address"]
        XCTAssertTrue(address.waitForExistence(timeout: 5), "The email form did not open")
        address.tap()
        address.typeText("alex@example.com")
        app.buttons["email-forgot"].tap()
        XCTAssertTrue(app.staticTexts["email-note"].waitForExistence(timeout: 5), "Forgot Password should say a link is on its way")

        // The link from the email opens the app.
        app.open(URL(string: "golfscorecard://login-callback?code=mock-reset")!)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let openButton = springboard.buttons["Open"]
        if openButton.waitForExistence(timeout: 3) { openButton.tap() }

        let newPassword = app.secureTextFields["new-password"]
        XCTAssertTrue(newPassword.waitForExistence(timeout: 10), "A reset link should open Set a New Password")
        newPassword.tap()
        newPassword.typeText("eagle123")
        let again = app.secureTextFields["new-password-again"]
        again.tap()
        again.typeText("eagle123")
        capture("e10-set-new-password")
        app.buttons["new-password-save"].tap()
        XCTAssertTrue(app.staticTexts["new-password-saved"].waitForExistence(timeout: 5), "Saving should say the password is saved")
        capture("e11-new-password-saved")
        app.buttons["new-password-close"].tap()
        let course = app.buttons["course-pompano-pines"]
        XCTAssertTrue(course.waitForExistence(timeout: 10), "Done should open the app, signed in")
        XCTAssertTrue(waitForHittable(course), "The account screen should be gone after the new password")
    }

    /// The open Duo (drawn at its size on the Pro Max): the account screen,
    /// and its email form.
    @MainActor
    func testOpenDuoAccountScreen() throws {
        guard Self.device.contains("Pro Max") else { return }
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-skipOnboarding", "-mockGroup", "-openDuoPreview", "-accountGate"]
        app.launch()
        let emailButton = app.buttons["sign-in-email"]
        XCTAssertTrue(emailButton.waitForExistence(timeout: 15), "The open Duo account screen did not load")
        sleep(1)
        capture("e12-open-duo-size-account-screen")
        emailButton.tap()
        XCTAssertTrue(app.textFields["email-address"].waitForExistence(timeout: 5), "The email form did not open")
        sleep(1)
        capture("e13-open-duo-size-email-create-account")
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

    private func waitForHittable(_ element: XCUIElement, timeout: TimeInterval = 10) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
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
