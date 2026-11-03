import XCTest
@testable import ScorecardCore

final class EmailCheckTests: XCTestCase {
    func testCleanTrimsAndLowercases() {
        XCTAssertEqual(EmailCheck.clean("  Alberto@Example.COM \n"), "alberto@example.com")
    }

    func testLooksValid() {
        for good in ["a@b.co", "alberto.aday@example.com", " Sam+golf@mail.example.org "] {
            XCTAssertTrue(EmailCheck.looksValid(good), good)
        }
        for bad in ["", "alberto", "alberto@", "@example.com", "al berto@example.com", "a@b", "a@.com", "a@b.c", "a@b@c.com"] {
            XCTAssertFalse(EmailCheck.looksValid(bad), bad)
        }
    }
}
