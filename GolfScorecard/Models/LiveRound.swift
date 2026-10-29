import ActivityKit
import Foundation

/// Starts, updates and ends the round's Lock Screen card (a Live Activity,
/// drawn by the RoundActivity extension). One round at a time.
@MainActor
enum LiveRound {
    /// Shows or updates the card for this round at this hole, unless the
    /// golfer turned the card off in Profile or in the phone's Settings.
    static func show(round: Round, course: Course, hole: Int) {
        guard UserDefaults.standard.object(forKey: SettingsKey.showOnLockScreen) as? Bool ?? true else {
            end()
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled, !round.isFinished else { return }
        let start = round.date.timeIntervalSinceReferenceDate
        let content = ActivityContent(state: state(round: round, course: course, hole: hole), staleDate: nil)
        let running = Activity<RoundActivityAttributes>.activities.filter { $0.activityState == .active || $0.activityState == .stale }
        if let activity = running.first(where: { $0.attributes.roundStart == start }) {
            Task { await activity.update(content) }
            return
        }
        // Another round's card is left over: only the round being played shows.
        for other in running { Task { await other.end(nil, dismissalPolicy: .immediate) } }
        let attributes = RoundActivityAttributes(courseName: round.courseName, roundStart: start)
        _ = try? Activity.request(attributes: attributes, content: content, pushType: nil)
    }

    /// Takes the card off the Lock Screen, after Finish or Delete, or when turned off.
    static func end() {
        for activity in Activity<RoundActivityAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }

    /// Ends any card left from a round that's gone or finished, for example
    /// after the app was closed in the middle of a round and it was deleted.
    static func endCards(exceptRoundsStartedAt starts: Set<Double>) {
        for activity in Activity<RoundActivityAttributes>.activities where !starts.contains(activity.attributes.roundStart) {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }

    static func state(round: Round, course: Course, hole: Int) -> RoundActivityAttributes.ContentState {
        let grid = round.grid
        var toPar = 0
        var thru = 0
        for courseHole in course.holes {
            let strokes = grid.strokes(player: 0, hole: courseHole.number)
            if strokes > 0 {
                toPar += strokes - courseHole.par
                thru += 1
            }
        }
        return RoundActivityAttributes.ContentState(
            hole: hole,
            par: course.hole(hole)?.par,
            strokes: grid.strokes(player: 0, hole: hole),
            total: grid.total(player: 0, holes: 1...StrokeGrid.holeCount),
            toPar: toPar,
            thru: thru
        )
    }
}

extension Notification.Name {
    /// Posted with the hole number when the Lock Screen card is tapped while
    /// its round is already open, so the round moves to that hole.
    static let showLiveRoundHole = Notification.Name("showLiveRoundHole")
}
