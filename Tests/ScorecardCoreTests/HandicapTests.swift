import XCTest
@testable import ScorecardCore

final class HandicapTests: XCTestCase {
    func testParsing() {
        XCTAssertEqual(HandicapIndex.parse("12.4"), 12.4)
        XCTAssertEqual(HandicapIndex.parse(" 18 "), 18)
        XCTAssertEqual(HandicapIndex.parse("9,8"), 9.8)
        XCTAssertEqual(HandicapIndex.parse("+1.2"), -1.2)
        XCTAssertNil(HandicapIndex.parse(""))
        XCTAssertNil(HandicapIndex.parse("abc"))
        XCTAssertNil(HandicapIndex.parse("-3"))
        XCTAssertNil(HandicapIndex.parse("60"))
    }

    func testFormatting() {
        XCTAssertEqual(HandicapIndex.format(12.4), "12.4")
        XCTAssertEqual(HandicapIndex.format(18), "18")
        XCTAssertEqual(HandicapIndex.format(-1.2), "+1.2")
        XCTAssertEqual(HandicapIndex.parse(HandicapIndex.format(-1.2)), -1.2)
    }

    func testStrokes() {
        XCTAssertEqual(HandicapIndex.strokes(index: 12.4, holesPlayed: 18), 12)
        XCTAssertEqual(HandicapIndex.strokes(index: 12.5, holesPlayed: 18), 13)
        XCTAssertEqual(HandicapIndex.strokes(index: 12.4, holesPlayed: 9), 6)
        XCTAssertEqual(HandicapIndex.strokes(index: -1.2, holesPlayed: 18), -1)
        XCTAssertNil(HandicapIndex.strokes(index: 12, holesPlayed: 5))
    }

    func testRecentNames() {
        let rounds = [["Alberto", "Sam", "Player 3"], ["alberto", "Jo", "sam"], ["Me", "Kim"]]
        XCTAssertEqual(PlayerNames.recent(from: rounds, excluding: ["Alberto", "Me"]), ["Sam", "Jo", "Kim"])
        XCTAssertEqual(PlayerNames.recent(from: rounds, excluding: ["Alberto"], limit: 2), ["Sam", "Jo"])
    }
}
