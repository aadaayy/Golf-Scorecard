import Foundation
import XCTest
@testable import ScorecardCore

/// The course library's index and the hole drawings downloaded courses bring.
final class LibraryTests: XCTestCase {
    private var repo: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // ScorecardCoreTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // repo root
    }

    /// Every built-in drawing must read, since the same files go into the library.
    func testEveryHoleDrawingReads() throws {
        let assets = repo.appendingPathComponent("GolfScorecard/Assets.xcassets")
        let files = (FileManager.default.enumerator(at: assets, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? [])
            .filter { $0.pathExtension == "svg" }
        XCTAssertFalse(files.isEmpty, "No hole drawings found")
        for file in files {
            let sketch = try HoleSketch.parse(Data(contentsOf: file))
            let name = file.lastPathComponent
            XCTAssertGreaterThan(sketch.elements.count, 5, "\(name) looks empty")
            XCTAssertGreaterThan(sketch.width, 0, name)
            XCTAssertGreaterThan(sketch.height, 0, name)
            XCTAssertTrue(sketch.elements.contains { $0.fill != nil }, "\(name) has nothing filled in")
            // Every path starts with a move.
            for element in sketch.elements {
                if case .path(let segments) = element.shape, let first = segments.first {
                    XCTAssertEqual(first.isMove, true, "\(name): a path doesn't start with a move")
                }
            }
        }
    }

    func testDrawingParts() throws {
        let svg = """
        <?xml version="1.0"?>
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="10 -20 200 400" width="100" height="200">
          <!-- a comment -->
          <path d="M10,20 l5,5 L1-2 C1,2 3,4 5,6 h10 v-5 Z" fill="#3E9A56" stroke="#2B7340" stroke-width="2.5" stroke-linejoin="round"/>
          <polyline points="1.0,2.0 3.0,4.0" fill="none" stroke="#1F3A2B" opacity="0.85" stroke-linecap="round"/>
          <line x1="1" y1="2" x2="3" y2="4" stroke="#fff"/>
          <circle cx="5" cy="6" r="4" fill="#FFFFFF"/>
        </svg>
        """
        let sketch = try HoleSketch.parse(svg)
        XCTAssertEqual(sketch.minX, 10)
        XCTAssertEqual(sketch.minY, -20)
        XCTAssertEqual(sketch.width, 200)
        XCTAssertEqual(sketch.height, 400)
        XCTAssertEqual(sketch.aspect, 0.5)
        XCTAssertEqual(sketch.elements.count, 4)

        let path = sketch.elements[0]
        typealias P = HoleSketch.Point
        XCTAssertEqual(path.shape, .path([
            .move(P(x: 10, y: 20)),
            .line(P(x: 15, y: 25)),
            .line(P(x: 1, y: -2)),
            .curve(P(x: 1, y: 2), P(x: 3, y: 4), to: P(x: 5, y: 6)),
            .line(P(x: 15, y: 6)),
            .line(P(x: 15, y: 1)),
            .close,
        ]))
        XCTAssertEqual(path.fill, HoleSketch.RGB(red: 0x3E / 255, green: 0x9A / 255, blue: 0x56 / 255))
        XCTAssertEqual(path.strokeWidth, 2.5)
        XCTAssertEqual(path.lineJoin, "round")

        let polyline = sketch.elements[1]
        XCTAssertNil(polyline.fill)
        XCTAssertEqual(polyline.opacity, 0.85)
        XCTAssertEqual(polyline.lineCap, "round")
        XCTAssertEqual(polyline.shape, .path([.move(P(x: 1, y: 2)), .line(P(x: 3, y: 4))]))

        XCTAssertNil(sketch.elements[2].fill, "A line has nothing to fill")
        XCTAssertEqual(sketch.elements[2].stroke, HoleSketch.RGB(red: 1, green: 1, blue: 1))
        XCTAssertEqual(sketch.elements[3].shape, .circle(center: P(x: 5, y: 6), radius: 4))
    }

    func testRelativeCurvesAndRepeatedPoints() throws {
        // After a move, more points are lines; relative curves count from where the pen is.
        let segments = try HoleSketch.segments(in: "m1 1 2 2c1 0 1 1 2 2z")
        typealias P = HoleSketch.Point
        XCTAssertEqual(segments, [
            .move(P(x: 1, y: 1)),
            .line(P(x: 3, y: 3)),
            .curve(P(x: 4, y: 3), P(x: 4, y: 4), to: P(x: 5, y: 5)),
            .close,
        ])
        XCTAssertEqual(try HoleSketch.numbers(in: "1e2,-3.5-.5"), [100, -3.5, -0.5])
    }

    func testDrawingsTheAppCantDraw() {
        XCTAssertThrowsError(try HoleSketch.parse("<svg viewBox=\"0 0 10 10\"><path d=\"M0 0 A 5 5 0 0 1 10 10\"/></svg>"))
        XCTAssertThrowsError(try HoleSketch.parse("<svg><path d=\"M0 0 L1 1\"/></svg>"), "No size")
        XCTAssertThrowsError(try HoleSketch.parse("<html></html>"))
        XCTAssertThrowsError(try HoleSketch.parse("<svg viewBox=\"0 0 10 10\"></svg>"), "Nothing in it")
        XCTAssertThrowsError(try HoleSketch.parse("<svg viewBox=\"0 0 10 10\"><circle r=\"1\" fill=\"green-ish\"/></svg>"))
    }

    private let indexJSON = """
    {
      "format": 1,
      "courses": [
        {"id": "pompano-pines", "name": "Pompano Beach Pines Course", "town": "Pompano Beach, FL",
         "holes": 18, "par": 72, "tees": ["Blue", "White"], "yards": {"Blue": 6612, "White": 6207},
         "version": 2, "folder": "courses/pompano-pines",
         "files": ["course.json", "pompano-pines-01.svg"], "bytes": 450000, "lat": 26.245107, "lng": -80.102812},
        {"id": "palm-aire", "name": "Palm-Aire Oaks", "town": "Pompano Beach, FL",
         "holes": 18, "par": 72, "tees": ["White"], "yards": {"White": 6000},
         "version": 1, "folder": "courses/palm-aire", "files": ["course.json"], "bytes": 20000},
        {"id": "crandon", "name": "Crandon Golf at Key Biscayne", "town": "Key Biscayne, FL",
         "holes": 18, "par": 72, "tees": ["White"], "yards": {"White": 6400},
         "version": 1, "folder": "courses/crandon", "files": ["course.json"], "bytes": 20000}
      ]
    }
    """

    func testIndexSearch() throws {
        let index = try CourseIndex.decode(from: Data(indexJSON.utf8))
        XCTAssertEqual(index.problems(), [])
        XCTAssertEqual(index.search("").map(\.id), ["crandon", "palm-aire", "pompano-pines"], "Sorted by name")
        XCTAssertEqual(index.search("pompano").map(\.id), ["palm-aire", "pompano-pines"], "Name or town")
        XCTAssertEqual(index.search("PINES pompano").map(\.id), ["pompano-pines"], "Every word must match")
        XCTAssertEqual(index.search("  key  biscayne ").map(\.id), ["crandon"])
        XCTAssertEqual(index.search("orlando"), [])

        let pines = try XCTUnwrap(index.entry(id: "pompano-pines"))
        XCTAssertTrue(pines.isNewer(than: 1))
        XCTAssertFalse(pines.isNewer(than: 2))
        XCTAssertEqual(pines.sizeText, "0.5 MB")
    }

    /// Courses with a location go on the map; the rest stay in the list only.
    func testIndexLocations() throws {
        var index = try CourseIndex.decode(from: Data(indexJSON.utf8))
        XCTAssertEqual(index.mapped.map(\.id), ["pompano-pines"])
        let pines = try XCTUnwrap(index.entry(id: "pompano-pines"))
        XCTAssertEqual(pines.lat, 26.245107)
        XCTAssertEqual(pines.lng, -80.102812)
        XCTAssertNil(index.entry(id: "crandon")?.lat, "An index with no locations still reads")

        index.courses[1].lat = 26.2
        index.courses[2].lat = 126
        index.courses[2].lng = -80
        XCTAssertEqual(index.problems().count, 2, "Half a location, and one off the globe")
    }

    func testIndexProblems() throws {
        var index = try CourseIndex.decode(from: Data(indexJSON.utf8))
        index.courses[0].folder = "../outside"
        index.courses[1].files = ["course.json", "../../escape.svg"]
        index.courses[2].files = ["drawing.svg"]
        index.courses.append(index.courses[2])
        XCTAssertEqual(index.problems().count, 5)

        XCTAssertTrue(CourseIndex.isSafeFolder("courses/pompano-pines"))
        XCTAssertFalse(CourseIndex.isSafeFolder("/courses"))
        XCTAssertFalse(CourseIndex.isSafeFolder("courses/../x"))
        XCTAssertFalse(CourseIndex.isSafeFolder("courses//x"))
        XCTAssertFalse(CourseIndex.isSafeFileName(".hidden"))
        XCTAssertFalse(CourseIndex.isSafeFileName("a/b.svg"))
    }

    /// Every course in the course library folder loads, passes every check and
    /// matches its index entry, and every hole drawing reads as a yardage book page.
    func testEveryLibraryCourseIsValid() throws {
        let library = repo.appendingPathComponent("course-library")
        let index = try CourseIndex.decode(from: Data(contentsOf: library.appendingPathComponent("index.json")))
        XCTAssertEqual(index.problems(), [])
        XCTAssertNotNil(index.entry(id: "pompano-pines"))
        XCTAssertNotNil(index.entry(id: "pompano-pines")?.lat, "Pompano Beach Pines should be on the map")
        for entry in index.courses {
            let folder = library.appendingPathComponent(entry.folder)
            let course = try Course.decode(from: Data(contentsOf: folder.appendingPathComponent("course.json")))
            XCTAssertEqual(course.problems(), [], entry.id)
            XCTAssertEqual(course.id, entry.id)
            XCTAssertEqual(course.holes.count, entry.holes, entry.id)
            XCTAssertEqual(course.tees, entry.tees, entry.id)
            for name in course.holes.compactMap(\.map) {
                let plan = HolePlan(sketch: try HoleSketch.parse(Data(contentsOf: folder.appendingPathComponent("\(name).svg"))))
                XCTAssertNotNil(plan.pin, "\(name) has no pin")
                XCTAssertGreaterThanOrEqual(plan.playLine.count, 2, "\(name) has no line of play")
            }
        }
    }

    /// A course whose yardages aren't known yet lists no tees, and is still good.
    func testCourseWithoutYardages() throws {
        let holes = (1...9).map { Hole(number: $0, par: 4, handicap: $0, yards: [:]) }
        let course = Course(id: "no-yards", name: "No Yards Yet", town: "Somewhere, FL", tees: [], holes: holes)
        XCTAssertEqual(course.problems(), [])
        XCTAssertEqual(course.par(holes: 1...9), 36)
        XCTAssertEqual(course.yards(tee: "", holes: 1...9), 0)

        var listed = course
        listed.tees = ["White"]
        XCTAssertFalse(listed.problems().isEmpty, "A listed tee still needs a yardage on every hole")
    }

    /// Course files without a version count as version 1.
    func testCourseVersion() throws {
        let file = repo.appendingPathComponent("GolfScorecard/Courses/pompano-pines.json")
        var course = try Course.decode(from: Data(contentsOf: file))
        XCTAssertGreaterThanOrEqual(course.currentVersion, 1)
        course.version = 0
        XCTAssertTrue(course.problems().contains("version must be 1 or more"))
    }
}

private extension HoleSketch.Segment {
    var isMove: Bool {
        if case .move = self { return true }
        return false
    }
}
