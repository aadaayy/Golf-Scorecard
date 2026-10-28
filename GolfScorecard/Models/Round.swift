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
    /// When the golfer tapped Finish. Nil while the round is still being played.
    var finishedAt: Date? = nil
    /// The first player's handicap index when the round started, for the net score.
    var playerHandicap: Double? = nil

    init(course: Course, tee: String, players: [String], playerHandicap: Double? = nil, date: Date = .now) {
        self.date = date
        self.courseID = course.id
        self.courseName = course.name
        self.tee = tee
        self.players = players
        self.strokes = StrokeGrid(playerCount: players.count).values
        self.playerHandicap = playerHandicap
    }

    var grid: StrokeGrid {
        get { StrokeGrid(playerCount: players.count, values: strokes) }
        set { strokes = newValue.values }
    }
}
