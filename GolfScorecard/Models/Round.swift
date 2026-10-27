import Foundation
import SwiftData

/// One round of golf, saved only on this phone.
@Model
final class Round {
    var date: Date
    var courseID: String
    var courseName: String
    var tee: String
    var players: [String]
    /// See `StrokeGrid` for the layout of this list.
    var strokes: [Int]

    init(course: Course, tee: String, players: [String], date: Date = .now) {
        self.date = date
        self.courseID = course.id
        self.courseName = course.name
        self.tee = tee
        self.players = players
        self.strokes = StrokeGrid(playerCount: players.count).values
    }

    var grid: StrokeGrid {
        get { StrokeGrid(playerCount: players.count, values: strokes) }
        set { strokes = newValue.values }
    }
}
