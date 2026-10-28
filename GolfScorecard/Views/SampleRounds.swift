#if DEBUG
import Foundation
import SwiftData

/// Made-up rounds for the automatic checks' screenshots of home and past
/// rounds. Only added when the app is launched with -sampleRounds.
enum SampleRounds {
    @MainActor
    static func insert(into context: ModelContext, library: CourseLibrary) {
        guard let course = library.course(id: "pompano-pines") ?? library.courses.first else { return }
        let day: TimeInterval = 24 * 60 * 60

        // A full round two weeks ago, with a friend.
        let full = Round(course: course, tee: "White", players: ["Alberto", "Sam"], playerHandicap: 14.2, date: .now - 14 * day)
        fill(full, player: 0, overPar: [1, 0, 2, 0, 1, 0, 1, 1, 0, 0, 1, 2, 0, 1, 0, 1, 0, 1], course: course)
        fill(full, player: 1, overPar: [0, 1, 1, 0, 2, 1, 0, 1, 1, 1, 0, 1, 1, 0, 2, 0, 1, 0], course: course)
        full.finishedAt = full.date + 4 * 60 * 60

        // A front nine last week.
        let nine = Round(course: course, tee: "Blue", players: ["Alberto"], playerHandicap: 14.2, date: .now - 7 * day)
        fill(nine, player: 0, overPar: [0, 1, 0, 2, 0, 1, -1, 1, 0], course: course)
        nine.finishedAt = nine.date + 2 * 60 * 60

        // Today's round, left after five holes.
        let today = Round(course: course, tee: "White", players: ["Alberto", "Sam", "Jo"], playerHandicap: 14.2, date: .now - 60 * 60)
        fill(today, player: 0, overPar: [1, 0, 0, 1, 2], course: course)
        fill(today, player: 1, overPar: [0, 1, 1, 0, 1], course: course)
        fill(today, player: 2, overPar: [2, 1, 0, 1, 1], course: course)

        for round in [full, nine, today] { context.insert(round) }
        try? context.save()
    }

    private static func fill(_ round: Round, player: Int, overPar: [Int], course: Course) {
        var grid = round.grid
        for (offset, over) in overPar.enumerated() {
            let hole = offset + 1
            grid.setStrokes((course.hole(hole)?.par ?? 4) + over, player: player, hole: hole)
        }
        round.grid = grid
    }
}
#endif
