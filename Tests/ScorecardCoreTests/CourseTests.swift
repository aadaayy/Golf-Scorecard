import Foundation
import XCTest
@testable import ScorecardCore

final class CourseTests: XCTestCase {
    /// The Courses folder in the app, found relative to this file.
    private var coursesFolder: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // ScorecardCoreTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // repo root
            .appendingPathComponent("GolfScorecard/Courses")
    }

    private func courseFiles() throws -> [URL] {
        try FileManager.default
            .contentsOfDirectory(at: coursesFolder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
    }

    func testThereIsAtLeastOneCourse() throws {
        XCTAssertFalse(try courseFiles().isEmpty, "No course files found in \(coursesFolder.path)")
    }

    /// Every course file in the app must load and pass every check.
    /// This is the test that catches a typo when a new course is added.
    func testEveryCourseFileIsValid() throws {
        var ids = Set<String>()
        for file in try courseFiles() {
            let course = try Course.decode(from: Data(contentsOf: file))
            XCTAssertEqual(course.problems(), [], "\(file.lastPathComponent) has problems")
            XCTAssertTrue(ids.insert(course.id).inserted, "Two course files use the id \(course.id)")
            XCTAssertEqual(file.deletingPathExtension().lastPathComponent, course.id,
                           "\(file.lastPathComponent) should be named after its id, \(course.id)")
        }
    }

    func testSampleCourseNumbers() throws {
        let course = try Course.decode(from: Data(contentsOf: coursesFolder.appendingPathComponent("sample-links.json")))
        XCTAssertEqual(course.holes.count, 18)
        XCTAssertEqual(course.par(holes: 1...9), 36)
        XCTAssertEqual(course.par(holes: 10...18), 36)
        XCTAssertEqual(course.par(holes: 1...18), 72)
        XCTAssertEqual(course.frontNine.count, 9)
        XCTAssertEqual(course.backNine.first?.number, 10)
        XCTAssertEqual(course.hole(1)?.par, 4)
    }

    func testProblemsCatchesCommonMistakes() {
        var course = Self.makeCourse()
        XCTAssertEqual(course.problems(), [])

        course.holes[2].handicap = course.holes[3].handicap
        XCTAssertTrue(course.problems().contains { $0.contains("handicaps") })

        course = Self.makeCourse()
        course.holes[4].yards["White"] = nil
        XCTAssertTrue(course.problems().contains { $0.contains("no yardage for White") })

        course = Self.makeCourse()
        course.holes.removeLast()
        XCTAssertTrue(course.problems().contains { $0.contains("expected 9 or 18") })

        course = Self.makeCourse()
        course.holes[0].par = 9
        XCTAssertTrue(course.problems().contains { $0.contains("par 9") })

        course = Self.makeCourse()
        course.id = "Bad ID"
        XCTAssertTrue(course.problems().contains { $0.contains("id") })
    }

    static func makeCourse() -> Course {
        let holes = (1...9).map { number in
            Hole(number: number, par: 4, handicap: number, yards: ["Blue": 400, "White": 370], map: nil)
        }
        return Course(id: "test-course", name: "Test Course", town: "Testville", tees: ["Blue", "White"], holes: holes)
    }
}
