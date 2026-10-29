import ActivityKit
import Foundation

/// The round being played, shown on the Lock Screen (and in the Dynamic Island)
/// as a Live Activity. Shared by the app, which starts and updates it, and the
/// RoundActivity extension, which draws it.
struct RoundActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// The hole the golfer is on.
        var hole: Int
        var par: Int?
        /// The first player's strokes on this hole, 0 before scoring it.
        var strokes: Int
        /// The first player's total so far.
        var total: Int
        /// Against par on the holes scored so far.
        var toPar: Int
        /// Holes scored so far.
        var thru: Int
        var keepScreenOn: Bool
    }

    var courseName: String
    /// When the round was started, which tells the app which round to open.
    var roundStart: Double

    /// The setting the Lock Screen toggle changes. The app reads it with
    /// `@AppStorage(SettingsKey.keepAwake)`.
    static let keepScreenOnKey = "keepScreenOnDuringRound"

    /// Opens the app on this round, at this hole.
    static func openURL(roundStart: Double, hole: Int) -> URL {
        var parts = URLComponents()
        parts.scheme = "golfscorecard"
        parts.host = "round"
        parts.queryItems = [
            URLQueryItem(name: "start", value: String(roundStart)),
            URLQueryItem(name: "hole", value: String(hole)),
        ]
        return parts.url!
    }
}

extension RoundActivityAttributes.ContentState {
    /// "+3", "-1" or "E".
    var toParText: String {
        toPar == 0 ? "E" : (toPar > 0 ? "+\(toPar)" : "\(toPar)")
    }
}
