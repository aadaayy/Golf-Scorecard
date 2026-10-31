import XCTest
@testable import ScorecardCore

final class OpenLayoutTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "OpenLayoutTests"

    override func setUp() {
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    func testBothStartOnHole() {
        XCTAssertEqual(OpenLayout.standard, .hole)
        XCTAssertNotEqual(TwoHalves.duoOpen.storageKey, TwoHalves.sideways.storageKey)
        XCTAssertFalse(TwoHalves.allCases.map(\.storageKey).contains(OpenLayout.oldStorageKey))
    }

    func testOldPickCarriesOverToBoth() {
        defaults.set("nine", forKey: OpenLayout.oldStorageKey)
        OpenLayout.carryOverOldSetting(in: defaults)
        XCTAssertEqual(defaults.string(forKey: TwoHalves.duoOpen.storageKey), "nine")
        XCTAssertEqual(defaults.string(forKey: TwoHalves.sideways.storageKey), "nine")
        XCTAssertNil(defaults.object(forKey: OpenLayout.oldStorageKey), "The old setting should be gone once carried over")
    }

    func testSeparatePicksAreKept() {
        defaults.set("hole", forKey: TwoHalves.sideways.storageKey)
        defaults.set("nine", forKey: OpenLayout.oldStorageKey)
        OpenLayout.carryOverOldSetting(in: defaults)
        XCTAssertEqual(defaults.string(forKey: TwoHalves.duoOpen.storageKey), "nine")
        XCTAssertEqual(defaults.string(forKey: TwoHalves.sideways.storageKey), "hole")
    }

    func testNothingToCarryOver() {
        OpenLayout.carryOverOldSetting(in: defaults)
        XCTAssertNil(defaults.object(forKey: TwoHalves.duoOpen.storageKey))
        XCTAssertNil(defaults.object(forKey: TwoHalves.sideways.storageKey))
    }

    func testUnknownOldValueIsDropped() {
        defaults.set("map", forKey: OpenLayout.oldStorageKey)
        OpenLayout.carryOverOldSetting(in: defaults)
        XCTAssertNil(defaults.object(forKey: TwoHalves.duoOpen.storageKey))
        XCTAssertNil(defaults.object(forKey: OpenLayout.oldStorageKey))
    }
}
