import Foundation

/// A golf course, as written in a course file in the Courses folder.
///
/// This file only uses Foundation, so the same code runs in the app and in
/// the logic tests on any computer.
struct Course: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var town: String
    var tees: [String]
    var holes: [Hole]
    /// Goes up by one each time the course file or its drawings change.
    /// Missing means 1. Downloaded courses update when the library has a higher one.
    var version: Int? = nil
}

struct Hole: Codable, Hashable {
    var number: Int
    var par: Int
    /// Stroke index from the paper card (1 = hardest). Optional because some cards don't list it.
    var handicap: Int?
    /// Stroke index for tees whose card row has its own (often the red tees), keyed by tee name.
    var handicaps: [String: Int]? = nil
    /// Yards for each tee, keyed by the tee's name.
    var yards: [String: Int]
    /// Name of the hole drawing in the asset catalog, if there is one yet.
    var map: String?
}

extension Course {
    static func decode(from data: Data) throws -> Course {
        try JSONDecoder().decode(Course.self, from: data)
    }

    var currentVersion: Int { version ?? 1 }

    var frontNine: [Hole] { holes.filter { $0.number <= 9 } }
    var backNine: [Hole] { holes.filter { $0.number >= 10 } }

    func hole(_ number: Int) -> Hole? {
        holes.first { $0.number == number }
    }

    /// The stroke index for a hole when playing from `tee`.
    func handicap(hole number: Int, tee: String) -> Int? {
        guard let hole = hole(number) else { return nil }
        return hole.handicaps?[tee] ?? hole.handicap
    }

    func par(holes range: ClosedRange<Int>) -> Int {
        holes.filter { range.contains($0.number) }.reduce(0) { $0 + $1.par }
    }

    func yards(tee: String, holes range: ClosedRange<Int>) -> Int {
        holes.filter { range.contains($0.number) }.reduce(0) { $0 + ($1.yards[tee] ?? 0) }
    }

    /// Everything wrong with this course file, in plain words. Empty means the file is good.
    func problems() -> [String] {
        var problems: [String] = []
        let allowedIDCharacters = Set("abcdefghijklmnopqrstuvwxyz0123456789-")

        if id.isEmpty || !id.allSatisfy({ allowedIDCharacters.contains($0) }) {
            problems.append("id must use only lowercase letters, numbers and hyphens")
        }
        if name.trimmingCharacters(in: .whitespaces).isEmpty {
            problems.append("name is empty")
        }
        if let version, version < 1 {
            problems.append("version must be 1 or more")
        }
        if tees.isEmpty {
            problems.append("no tees listed")
        }
        if holes.count != 9 && holes.count != 18 {
            problems.append("has \(holes.count) holes; expected 9 or 18")
        }
        let numbers = holes.map(\.number)
        if numbers != Array(1...max(holes.count, 1)) {
            problems.append("hole numbers must run 1 to \(holes.count) in order")
        }
        for hole in holes {
            if !(3...6).contains(hole.par) {
                problems.append("hole \(hole.number): par \(hole.par) looks wrong")
            }
            for tee in tees {
                guard let yards = hole.yards[tee] else {
                    problems.append("hole \(hole.number): no yardage for \(tee) tee")
                    continue
                }
                if !(50...750).contains(yards) {
                    problems.append("hole \(hole.number): \(yards) yards from \(tee) looks wrong")
                }
            }
            for tee in hole.yards.keys where !tees.contains(tee) {
                problems.append("hole \(hole.number): yardage for unknown tee \(tee)")
            }
        }
        let handicaps = holes.compactMap(\.handicap)
        if !handicaps.isEmpty {
            if handicaps.count != holes.count {
                problems.append("some holes have a handicap and some don't")
            } else if Set(handicaps) != Set(1...holes.count) {
                problems.append("handicaps must use each number from 1 to \(holes.count) once")
            } else {
                // Tees with their own handicap row must also use each number once.
                let teesWithOwnRow = Set(holes.flatMap { $0.handicaps?.keys.map { $0 } ?? [] })
                for tee in teesWithOwnRow.sorted() {
                    if !tees.contains(tee) {
                        problems.append("handicaps for unknown tee \(tee)")
                        continue
                    }
                    let row = holes.compactMap { handicap(hole: $0.number, tee: tee) }
                    if Set(row) != Set(1...holes.count) || row.count != holes.count {
                        problems.append("\(tee) handicaps must use each number from 1 to \(holes.count) once")
                    }
                }
            }
        }
        let maps = holes.compactMap(\.map)
        if Set(maps).count != maps.count {
            problems.append("two holes use the same map drawing")
        }
        return problems
    }
}
