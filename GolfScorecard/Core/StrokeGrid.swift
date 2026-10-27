import Foundation

/// Strokes for every player on every hole.
///
/// Stored as one flat list so a round saves simply: player 1's 18 holes,
/// then player 2's, and so on. 0 means "not entered yet".
struct StrokeGrid: Equatable {
    static let holeCount = 18
    static let maxStrokes = 20

    let playerCount: Int
    private(set) var values: [Int]

    init(playerCount: Int, values: [Int]? = nil) {
        self.playerCount = max(playerCount, 0)
        let needed = self.playerCount * Self.holeCount
        if let values, values.count == needed {
            self.values = values
        } else {
            self.values = Array(repeating: 0, count: needed)
        }
    }

    private func index(player: Int, hole: Int) -> Int? {
        guard (0..<playerCount).contains(player), (1...Self.holeCount).contains(hole) else { return nil }
        return player * Self.holeCount + (hole - 1)
    }

    func strokes(player: Int, hole: Int) -> Int {
        guard let i = index(player: player, hole: hole) else { return 0 }
        return values[i]
    }

    mutating func setStrokes(_ strokes: Int, player: Int, hole: Int) {
        guard let i = index(player: player, hole: hole) else { return }
        values[i] = min(max(strokes, 0), Self.maxStrokes)
    }

    /// Total of the holes entered so far in the range.
    func total(player: Int, holes range: ClosedRange<Int>) -> Int {
        range.reduce(0) { $0 + strokes(player: player, hole: $1) }
    }

    func holesPlayed(player: Int, holes range: ClosedRange<Int>) -> Int {
        range.filter { strokes(player: player, hole: $0) > 0 }.count
    }

    /// Strokes over (+) or under (-) par for the holes entered so far, or nil if none are entered.
    func toPar(player: Int, course: Course) -> Int? {
        let played = course.holes.filter { strokes(player: player, hole: $0.number) > 0 }
        guard !played.isEmpty else { return nil }
        let strokesTaken = played.reduce(0) { $0 + strokes(player: player, hole: $1.number) }
        let par = played.reduce(0) { $0 + $1.par }
        return strokesTaken - par
    }
}
