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

    /// Pompano Beach Pines, checked against the totals printed on the paper card.
    func testPompanoPinesMatchesTheCard() throws {
        let course = try Course.decode(from: Data(contentsOf: coursesFolder.appendingPathComponent("pompano-pines.json")))
        XCTAssertEqual(course.holes.count, 18)
        XCTAssertEqual(course.tees, ["Gold", "Blue", "White", "Brown", "Red"])
        // tee: (OUT, IN, TOT) as printed on the card
        let cardTotals: [String: (Int, Int, Int)] = [
            "Gold": (3506, 3613, 7119),
            "Blue": (3231, 3381, 6612),
            "White": (3050, 3157, 6207),
            "Brown": (2726, 2829, 5555),
            "Red": (2446, 2626, 5072),
        ]
        for (tee, totals) in cardTotals {
            XCTAssertEqual(course.yards(tee: tee, holes: 1...9), totals.0, "\(tee) OUT")
            XCTAssertEqual(course.yards(tee: tee, holes: 10...18), totals.1, "\(tee) IN")
            XCTAssertEqual(course.yards(tee: tee, holes: 1...18), totals.2, "\(tee) TOT")
        }
        XCTAssertEqual(course.par(holes: 1...9), 36)
        XCTAssertEqual(course.par(holes: 10...18), 36)
        XCTAssertEqual(course.par(holes: 1...18), 72)
        XCTAssertEqual((1...18).map { course.hole($0)!.par }, [5, 4, 3, 4, 4, 5, 3, 4, 4, 5, 4, 5, 4, 4, 3, 4, 3, 4])
        XCTAssertEqual((1...18).map { course.handicap(hole: $0, tee: "White")! },
                       [6, 12, 16, 10, 8, 2, 18, 4, 14, 7, 3, 1, 9, 5, 11, 15, 17, 13])
        XCTAssertEqual((1...18).map { course.handicap(hole: $0, tee: "Red")! },
                       [6, 14, 16, 10, 8, 2, 18, 4, 12, 5, 3, 1, 7, 13, 15, 9, 17, 11])
        XCTAssertEqual(course.hole(7)?.yards["Red"], 97)
        XCTAssertEqual((1...18).map { course.hole($0)!.map }, (1...18).map { String(format: "pompano-pines-%02d", $0) })
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
        course.holes[0].handicaps = ["White": 2]
        XCTAssertTrue(course.problems().contains { $0.contains("White handicaps") })

        course = Self.makeCourse()
        course.holes[0].handicaps = ["Green": 1]
        XCTAssertTrue(course.problems().contains { $0.contains("unknown tee Green") })

        course = Self.makeCourse()
        course.holes[0].handicaps = ["White": 2]
        course.holes[1].handicaps = ["White": 1]
        XCTAssertEqual(course.problems(), [], "Swapping two red-tee style handicaps is fine")

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
