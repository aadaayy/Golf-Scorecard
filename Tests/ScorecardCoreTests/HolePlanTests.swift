import Foundation
import XCTest
@testable import ScorecardCore

/// The yardage book map: every built-in hole must read as rough, fairway,
/// green and pin, with a line of play and arcs that land on it.
final class HolePlanTests: XCTestCase {
    private var repo: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // ScorecardCoreTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // repo root
    }

    func testEveryBuiltInHoleReadsAsAYardageBookPage() throws {
        let courses = repo.appendingPathComponent("GolfScorecard/Courses")
        let assets = repo.appendingPathComponent("GolfScorecard/Assets.xcassets")
        let drawings = (FileManager.default.enumerator(at: assets, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? [])
            .filter { $0.pathExtension == "svg" }
        var checked = 0
        for file in try FileManager.default.contentsOfDirectory(at: courses, includingPropertiesForKeys: nil)
            where file.pathExtension == "json" {
            let course = try Course.decode(from: Data(contentsOf: file))
            for hole in course.holes {
                guard let map = hole.map, let drawing = drawings.first(where: { $0.deletingPathExtension().lastPathComponent == map }) else { continue }
                let plan = HolePlan(sketch: try HoleSketch.parse(Data(contentsOf: drawing)))
                let name = "\(course.id) hole \(hole.number)"
                let backTee = hole.yards.values.max() ?? 0

                XCTAssertNotNil(plan.green, "\(name) has no green")
                XCTAssertNotNil(plan.pin, "\(name) has no pin")
                XCTAssertNotNil(plan.greenCenter, "\(name) has no middle of the green")
                XCTAssertTrue(plan.parts.contains { $0.kind == .rough }, "\(name) has no rough")
                XCTAssertGreaterThanOrEqual(plan.playLine.count, 2, "\(name) has no line of play")
                XCTAssertGreaterThan(plan.trees.count, 10, "\(name) has hardly any trees")
                XCTAssertGreaterThan(plan.width, 0, name)
                XCTAssertGreaterThan(plan.height, 0, name)

                let depth = try XCTUnwrap(plan.greenDepth(backTeeYards: backTee), "\(name) green depth")
                XCTAssertTrue((12...60).contains(depth), "\(name): green is \(depth) yards deep")

                // Every arc the map draws crosses the line of play, and only par 4s
                // and 5s are long enough to need one past 100.
                let arcs = plan.arcYards(backTeeYards: backTee)
                if hole.par >= 4 { XCTAssertFalse(arcs.isEmpty, "\(name) has no yardage arcs") }
                let perYard = try XCTUnwrap(plan.unitsPerYard(backTeeYards: backTee), name)
                for yards in arcs {
                    XCTAssertNotNil(plan.crossing(radius: Double(yards) * perYard), "\(name): the \(yards) arc misses the line of play")
                }
                checked += 1
            }
        }
        XCTAssertGreaterThan(checked, 0, "No built-in hole drawings were checked")
    }

    /// Trees stay off the course: none stands on the fairway, the green or in the water.
    func testTreesStayOffTheCourse() throws {
        let file = repo.appendingPathComponent("GolfScorecard/Assets.xcassets/Pompano Pines/pompano-pines-01.dataset/pompano-pines-01.svg")
        let plan = HolePlan(sketch: try HoleSketch.parse(Data(contentsOf: file)))
        let ground = plan.parts.filter { [HolePlan.Kind.fairway, .green, .water, .sand].contains($0.kind) }
        for tree in plan.trees {
            for part in ground {
                XCTAssertFalse(HolePlan.contains(part.outline, tree.center), "A tree stands on the \(part.kind)")
            }
        }
    }
}
