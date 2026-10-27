import XCTest
@testable import ScorecardCore

final class StrokeGridTests: XCTestCase {
    func testStartsEmpty() {
        let grid = StrokeGrid(playerCount: 2)
        XCTAssertEqual(grid.values.count, 36)
        XCTAssertEqual(grid.total(player: 0, holes: 1...18), 0)
        XCTAssertEqual(grid.holesPlayed(player: 1, holes: 1...18), 0)
    }

    func testTotalsByNine() {
        var grid = StrokeGrid(playerCount: 2)
        grid.setStrokes(5, player: 0, hole: 1)
        grid.setStrokes(4, player: 0, hole: 9)
        grid.setStrokes(3, player: 0, hole: 10)
        grid.setStrokes(6, player: 1, hole: 1)
        XCTAssertEqual(grid.total(player: 0, holes: 1...9), 9)
        XCTAssertEqual(grid.total(player: 0, holes: 10...18), 3)
        XCTAssertEqual(grid.total(player: 0, holes: 1...18), 12)
        XCTAssertEqual(grid.total(player: 1, holes: 1...18), 6)
        XCTAssertEqual(grid.holesPlayed(player: 0, holes: 1...18), 3)
    }

    func testPlayersDoNotOverlap() {
        var grid = StrokeGrid(playerCount: 4)
        for player in 0..<4 {
            for hole in 1...18 { grid.setStrokes(player + 1, player: player, hole: hole) }
        }
        for player in 0..<4 {
            XCTAssertEqual(grid.total(player: player, holes: 1...18), (player + 1) * 18)
        }
    }

    func testClampsAndIgnoresBadInput() {
        var grid = StrokeGrid(playerCount: 1)
        grid.setStrokes(99, player: 0, hole: 1)
        XCTAssertEqual(grid.strokes(player: 0, hole: 1), StrokeGrid.maxStrokes)
        grid.setStrokes(-3, player: 0, hole: 1)
        XCTAssertEqual(grid.strokes(player: 0, hole: 1), 0)
        grid.setStrokes(4, player: 5, hole: 1)
        grid.setStrokes(4, player: 0, hole: 19)
        XCTAssertEqual(grid.total(player: 0, holes: 1...18), 0)
        XCTAssertEqual(grid.strokes(player: 7, hole: 30), 0)
    }

    func testWrongSizedSaveStartsFresh() {
        let grid = StrokeGrid(playerCount: 2, values: [1, 2, 3])
        XCTAssertEqual(grid.values, Array(repeating: 0, count: 36))
    }

    func testToPar() {
        let course = CourseTests.makeCourse() // par 4 on every hole
        var grid = StrokeGrid(playerCount: 1)
        XCTAssertNil(grid.toPar(player: 0, course: course))
        grid.setStrokes(5, player: 0, hole: 1)
        grid.setStrokes(3, player: 0, hole: 2)
        grid.setStrokes(6, player: 0, hole: 3)
        XCTAssertEqual(grid.toPar(player: 0, course: course), 2)
    }
}
