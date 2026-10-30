import XCTest

/// Find Courses: starting with no courses, find Pompano Beach Pines in the
/// course library, download it, play it, and remove it again.
///
/// The automatic checks make a copy of the library on the test Mac
/// (Tools/CourseLibrary/make_library.py) and pass its address in
/// COURSE_LIBRARY_URL, so the checks don't depend on the internet.
final class FindCoursesUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }

    private func launch(_ extra: [String] = []) throws -> XCUIApplication {
        let library = try XCTUnwrap(ProcessInfo.processInfo.environment["COURSE_LIBRARY_URL"],
                                    "COURSE_LIBRARY_URL isn't set; the checks set it to a copy of the course library")
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-skipOnboarding", "-noBuiltInCourses", "-courseLibraryURL", library] + extra
        app.launch()
        return app
    }

    @MainActor
    func testFindDownloadPlayAndRemove() throws {
        let app = try launch()

        // Play starts with no courses, and offers Find Courses.
        let find = app.buttons["find-courses"]
        XCTAssertTrue(find.waitForExistence(timeout: 15), "Play should offer Find Courses")
        XCTAssertFalse(app.buttons["course-pompano-pines"].exists, "Play should start with no courses in this check")
        capture("f1-play-no-courses")
        find.tap()

        // The library's list. Tapping a course that isn't on the phone downloads it.
        let row = app.buttons["library-course-pompano-pines"]
        XCTAssertTrue(row.waitForExistence(timeout: 20), "Pompano Beach Pines is missing from Find Courses")
        capture("f2-find-courses")
        row.tap()
        XCTAssertTrue(wait(for: row, label: "On your phone", timeout: 30), "The download didn't finish")
        capture("f4-downloaded")

        // Sideways: the list on the left, the downloaded course on the right.
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(2)
        if app.otherElements["course-preview"].waitForExistence(timeout: 5) {
            XCTAssertTrue(app.buttons["play-course"].exists, "The downloaded course should have Play")
            capture("f4b-sideways-find-courses")
        } else {
            XCTAssertTrue(Self.isDuo, "A sideways iPhone should show the course beside the list")
        }
        XCUIDevice.shared.orientation = .portrait
        sleep(2)

        // Back on Play, the course is there, marked as downloaded.
        back(in: app)
        let course = app.buttons["course-pompano-pines"]
        XCTAssertTrue(course.waitForExistence(timeout: 5), "The downloaded course should be on Play")
        XCTAssertTrue(course.label.contains("Downloaded"), "Play should mark the course as downloaded")
        capture("f5-play-downloaded")

        // Play it: the hole drawings came with the download.
        course.tap()
        let start = app.buttons["start-round"]
        XCTAssertTrue(start.waitForExistence(timeout: 5), "The Start Round button is missing")
        start.tap()
        let tabBarMap = app.tabBars.buttons["Map"]
        let mapTab = tabBarMap.waitForExistence(timeout: 5) ? tabBarMap : app.buttons["Map"].firstMatch
        XCTAssertTrue(mapTab.waitForExistence(timeout: 5), "The Map tab is missing")
        mapTab.tap()
        XCTAssertTrue(app.images["Map of hole 1"].firstMatch.waitForExistence(timeout: 5),
                      "The downloaded hole drawing should show, not the placeholder")
        capture("f6-downloaded-course-map")
        app.buttons["close-round"].tap()

        // Remove it: swipe, then confirm.
        XCTAssertTrue(course.waitForExistence(timeout: 5))
        course.swipeLeft()
        let remove = app.buttons["Remove"]
        XCTAssertTrue(remove.waitForExistence(timeout: 5), "A downloaded course should have Remove")
        remove.tap()
        let confirm = app.buttons["Remove Course"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "Remove should ask first")
        confirm.tap()
        XCTAssertTrue(waitForGone(course), "The removed course should leave Play")

        // Search the library by name or town.
        find.tap()
        XCTAssertTrue(row.waitForExistence(timeout: 20))
        XCTAssertFalse(row.label.contains("On your phone"), "The removed course should be downloadable again")
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5), "Find Courses should have a search field")
        search.tap()
        search.typeText("Orlando")
        XCTAssertTrue(waitForGone(row, timeout: 15),
                      "Searching for another town should hide Pompano Beach Pines (the search reads \(String(describing: search.value)))")
        search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 7) + "pompano")
        XCTAssertTrue(row.waitForExistence(timeout: 5), "Searching by town should find Pompano Beach Pines")
        capture("f3-search")
    }

    /// One real download from the course library on GitHub, on the iPhone Pro
    /// only, so the checks know the published library works.
    @MainActor
    func testDownloadFromGitHub() throws {
        let device = ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] ?? ""
        try XCTSkipUnless(device.contains("Pro") && !device.contains("Max"), "The real download is checked on the iPhone Pro only")
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-skipOnboarding", "-noBuiltInCourses"]
        app.launch()

        let find = app.buttons["find-courses"]
        XCTAssertTrue(find.waitForExistence(timeout: 15), "Play should offer Find Courses")
        find.tap()
        // The real library holds every Florida course, so find this one by name.
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 30), "Find Courses should have a search field")
        capture("g0-github-full-list")
        search.tap()
        search.typeText("pompano pines")
        let row = app.buttons["library-course-pompano-pines"]
        XCTAssertTrue(row.waitForExistence(timeout: 30), "Pompano Beach Pines is missing from the library on GitHub")
        capture("g1-github-find-courses")
        row.tap()
        XCTAssertTrue(wait(for: row, label: "On your phone", timeout: 60), "The download from GitHub didn't finish")
        closeSearch(in: app)
        back(in: app)
        let course = app.buttons["course-pompano-pines"]
        XCTAssertTrue(course.waitForExistence(timeout: 5), "The course downloaded from GitHub should be on Play")
        capture("g2-github-downloaded")
        course.tap()
        XCTAssertTrue(app.buttons["start-round"].waitForExistence(timeout: 5), "The downloaded course should open")

        // A Florida course from open data, with hole drawings from OpenStreetMap.
        back(in: app)
        find.tap()
        XCTAssertTrue(search.waitForExistence(timeout: 30))
        search.tap()
        search.typeText("dubsdread")
        let florida = app.buttons["library-course-dubsdread-golf-course"]
        XCTAssertTrue(florida.waitForExistence(timeout: 30), "Dubsdread is missing from the library on GitHub")
        florida.tap()
        XCTAssertTrue(wait(for: florida, label: "On your phone", timeout: 60), "The Florida course didn't download")
        closeSearch(in: app)
        back(in: app)
        let dubsdread = app.buttons["course-dubsdread-golf-course"]
        XCTAssertTrue(dubsdread.waitForExistence(timeout: 5), "The Florida course should be on Play")
        dubsdread.tap()
        XCTAssertTrue(app.buttons["start-round"].waitForExistence(timeout: 5), "The Florida course should open")
        capture("g3-florida-course")
    }

    /// Find Courses at the open iPhone Duo's size, drawn on the Pro Max (see OpenDuoPreview).
    @MainActor
    func testOpenDuoFindCourses() throws {
        let device = ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] ?? ""
        try XCTSkipUnless(device.contains("Pro Max"), "The open Duo pictures are taken on the Pro Max only")
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = try launch(["-openDuoPreview", "-home"])

        let find = app.buttons["find-courses"]
        XCTAssertTrue(find.waitForExistence(timeout: 15), "Play should offer Find Courses")
        find.tap()
        let detail = app.otherElements["library-detail"]
        XCTAssertTrue(detail.waitForExistence(timeout: 20), "The picked course should show beside the list")
        sleep(1)
        capture("f7-open-duo-size-find-courses")

        detail.buttons["download-pompano-pines"].tap()
        XCTAssertTrue(app.otherElements["course-preview"].waitForExistence(timeout: 30),
                      "Once downloaded, the whole course should show beside the list")
        sleep(1)
        capture("f8-open-duo-size-downloaded")

        back(in: app)
        XCTAssertTrue(app.buttons["course-pompano-pines"].waitForExistence(timeout: 5), "The downloaded course should be on Play")
        sleep(1)
        capture("f9-open-duo-size-play")
    }

    /// The map in Find Courses, with the whole Florida library: every course a
    /// dot, the search zooming in on a town (Tampa, as if you didn't know its
    /// courses' names), and tapping a dot to see a course and download it.
    @MainActor
    func testBrowseMap() throws {
        let app = try launchWithWholeLibrary()
        let find = app.buttons["find-courses"]
        XCTAssertTrue(find.waitForExistence(timeout: 15), "Play should offer Find Courses")
        find.tap()
        showMap(in: app)

        let caption = app.staticTexts["map-caption"]
        XCTAssertTrue(caption.waitForExistence(timeout: 20), "The map should say how many courses are on it")
        XCTAssertTrue(caption.label.contains("courses"), "The caption reads \(caption.label)")
        sleep(4)  // the map tiles
        capture("m1-map-florida")

        // A town you don't know: the dots narrow to it and the map zooms in.
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5), "The search should stay with the map")
        search.tap()
        search.typeText("Tampa\n")
        XCTAssertTrue(wait(for: caption, label: "found", timeout: 10), "Searching should narrow the map (\(caption.label))")
        sleep(4)
        capture("m2-map-tampa")

        // Tap a course's dot: its card, with Download.
        let dot = element("map-course-carrollwood-country-club-pines-cypress-course", in: app)
        XCTAssertTrue(dot.waitForExistence(timeout: 10), "Carrollwood should be a dot on the map of Tampa")
        dot.tap()
        let card = element("map-course-card", in: app)
        XCTAssertTrue(card.waitForExistence(timeout: 5), "Tapping a dot should show the course")
        sleep(1)
        capture("m3-map-course-card")
        let download = app.buttons["download-carrollwood-country-club-pines-cypress-course"]
        XCTAssertTrue(download.waitForExistence(timeout: 5), "The card should have Download")
        download.tap()
        XCTAssertTrue(app.buttons["map-play-carrollwood-country-club-pines-cypress-course"].waitForExistence(timeout: 30),
                      "Once downloaded, the card should offer Play")
        sleep(1)
        capture("m4-map-downloaded")
        app.buttons["map-card-close"].tap()
        XCTAssertTrue(waitForGone(card), "Close should put the card away")

        // Two courses at one club share a dot: tapping it asks which.
        let cluster = element("map-cluster", in: app)
        if cluster.waitForExistence(timeout: 5) {
            cluster.tap()
            let north = app.buttons["North At Bay Palms Golf Complex"]
            XCTAssertTrue(north.waitForExistence(timeout: 5), "Courses at one spot should be listed to pick from")
            capture("m5-map-two-courses-one-spot")
            north.tap()
            XCTAssertTrue(card.waitForExistence(timeout: 5), "Picking one should show it")
        }

        // Sideways: the map on the left, the picked course on the right.
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(3)
        capture("m6-sideways-map")
        XCUIDevice.shared.orientation = .portrait
        sleep(1)
    }

    /// The map at the open iPhone Duo's size, drawn on the Pro Max.
    @MainActor
    func testOpenDuoMap() throws {
        let device = ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] ?? ""
        try XCTSkipUnless(device.contains("Pro Max"), "The open Duo pictures are taken on the Pro Max only")
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = try launchWithWholeLibrary(["-openDuoPreview", "-home"])
        let find = app.buttons["find-courses"]
        XCTAssertTrue(find.waitForExistence(timeout: 15), "Play should offer Find Courses")
        find.tap()
        showMap(in: app)
        XCTAssertTrue(element("map-hint", in: app).waitForExistence(timeout: 20), "The right half should say to tap a course")
        sleep(4)
        capture("m7-open-duo-size-map")

        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Tampa\n")
        let dot = element("map-course-carrollwood-country-club-pines-cypress-course", in: app)
        XCTAssertTrue(dot.waitForExistence(timeout: 10), "Carrollwood should be a dot on the map of Tampa")
        sleep(3)
        dot.tap()
        XCTAssertTrue(app.otherElements["library-detail"].waitForExistence(timeout: 5),
                      "The course tapped on the map should show on the right half")
        sleep(1)
        capture("m8-open-duo-size-map-course")
    }

    /// The checks pass the repository's whole course library in WHOLE_COURSE_LIBRARY_URL.
    private func launchWithWholeLibrary(_ extra: [String] = []) throws -> XCUIApplication {
        let library = try XCTUnwrap(ProcessInfo.processInfo.environment["WHOLE_COURSE_LIBRARY_URL"],
                                    "WHOLE_COURSE_LIBRARY_URL isn't set; the checks set it to the repository's course-library folder")
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-skipOnboarding", "-noBuiltInCourses", "-courseLibraryURL", library] + extra
        app.launch()
        return app
    }

    private func showMap(in app: XCUIApplication) {
        let mapSide = app.segmentedControls.buttons["Map"].firstMatch
        XCTAssertTrue(mapSide.waitForExistence(timeout: 20), "Find Courses should have List | Map")
        mapSide.tap()
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// The Back button is in the navigation bar on most iPhones and at the side on the Duo.
    private func back(in app: XCUIApplication) {
        let side = app.buttons["BackButton"].firstMatch
        let button = side.exists ? side : app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(button.waitForExistence(timeout: 5), "Back is missing")
        button.tap()
        sleep(1)
    }

    /// While the search field is in use the navigation bar is hidden, so end the search before going back.
    private func closeSearch(in app: XCUIApplication) {
        for name in ["Cancel", "Close"] {
            let button = app.buttons[name].firstMatch
            if button.exists {
                button.tap()
                sleep(1)
                return
            }
        }
    }

    private func waitForGone(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter().wait(for: [gone], timeout: timeout) == .completed
    }

    private func wait(for element: XCUIElement, label: String, timeout: TimeInterval) -> Bool {
        let shows = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", label), object: element)
        return XCTWaiter().wait(for: [shows], timeout: timeout) == .completed
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
