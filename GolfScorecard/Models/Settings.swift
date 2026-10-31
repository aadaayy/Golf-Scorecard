import Foundation

/// Names of the golfer's settings, saved with `@AppStorage` on this phone.
enum SettingsKey {
    /// Set once the welcome pages have been seen or skipped.
    static let onboarded = "onboarded"
    static let playerName = "playerName"
    /// The handicap index as typed, "" when there isn't one. See `HandicapIndex`.
    static let handicap = "handicap"
    /// The tee picked first when starting a round, if the course has it.
    static let usualTee = "usualTee"
    /// Shows the round being played on the Lock Screen (a Live Activity). On unless turned off.
    static let showOnLockScreen = "showRoundOnLockScreen"
    /// Find Courses opens on the map instead of the list, once it was last left on the map.
    static let findCoursesOnMap = "findCoursesOnMap"

    /// Every setting, so "Erase everything" and the UI tests can clear them.
    static let all = [onboarded, playerName, handicap, usualTee, showOnLockScreen, findCoursesOnMap,
                      TwoHalves.duoOpen.storageKey, TwoHalves.sideways.storageKey, OpenLayout.oldStorageKey]

    static func eraseAll() {
        for key in all { UserDefaults.standard.removeObject(forKey: key) }
    }
}

extension Round {
    /// Finished rounds are kept as they were played; unfinished ones can be picked up again.
    var isFinished: Bool { finishedAt != nil }

    /// The last hole anyone has a score on, so a resumed round opens where it left off.
    var lastScoredHole: Int {
        let grid = grid
        return (1...StrokeGrid.holeCount).last { hole in
            players.indices.contains { grid.strokes(player: $0, hole: hole) > 0 }
        } ?? 0
    }
}
