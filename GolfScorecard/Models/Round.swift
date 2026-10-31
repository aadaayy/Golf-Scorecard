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
    /// Set for a group round: its id in the group-round database (see GroupSession).
    var groupRoundID: String? = nil
    /// The six-letter code friends join a group round with.
    var groupCode: String? = nil
    /// This phone's row on a group round's card. Solo rounds are always row 0.
    var groupSeat: Int = 0
    /// Whether this phone started the group round, so Finish closes it to new players.
    var groupIsHost: Bool = false

    init(course: Course, tee: String, players: [String], playerHandicap: Double? = nil, date: Date = .now) {
        self.date = date
        self.courseID = course.id
        self.courseName = course.name
        self.tee = tee
        self.players = players
        self.strokes = StrokeGrid(playerCount: players.count).values
        self.playerHandicap = playerHandicap
    }

    var isGroupRound: Bool { groupRoundID != nil }

    /// The golfer holding this phone: row 0, or their seat in a group round.
    var me: Int { isGroupRound ? min(groupSeat, max(players.count - 1, 0)) : 0 }

    var grid: StrokeGrid {
        get { StrokeGrid(playerCount: players.count, values: strokes) }
        set { strokes = newValue.values }
    }
}
