import Foundation

/// The six-letter code friends type to join a group round, and the link that
/// carries it.
///
/// Codes use letters and digits that can't be mixed up when read off a phone
/// (no I, L, O, 0 or 1). The database makes them; see supabase/migrations.
enum JoinCode {
    static let length = 6
    static let alphabet = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")

    /// What someone typed, ready to send: in capitals, with spaces and dashes
    /// taken out, and no longer than a code.
    static func clean(_ typed: String) -> String {
        String(typed.uppercased().compactMap { character -> Character? in
            switch character {
            case " ", "-", "_": return nil
            default: return character
            }
        }.prefix(length))
    }

    static func isValid(_ code: String) -> Bool {
        code.count == length && code.allSatisfy(alphabet.contains)
    }

    /// golfscorecard://join?code=ABC234, which opens the app at Join a Group Round.
    static func link(for code: String) -> URL {
        var components = URLComponents()
        components.scheme = "golfscorecard"
        components.host = "join"
        components.queryItems = [URLQueryItem(name: "code", value: code)]
        return components.url!
    }

    /// The code in a join link, or nil for any other link.
    static func code(in url: URL) -> String? {
        guard url.scheme == "golfscorecard", url.host == "join",
              let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "code" })?.value else { return nil }
        let code = clean(value)
        return isValid(code) ? code : nil
    }

    /// Shown with the code on screen, in threes: "ABC 234".
    static func spaced(_ code: String) -> String {
        guard code.count == length else { return code }
        return "\(code.prefix(3)) \(code.suffix(3))"
    }
}

/// Someone playing in a group round: their seat is their row on the card.
struct GroupPlayer: Equatable, Hashable, Sendable {
    var userID: String
    var seat: Int
    var name: String
}

/// One player's score on one hole, as it comes from the group.
struct GroupScore: Equatable, Hashable, Sendable {
    var userID: String
    var hole: Int
    var strokes: Int
}

/// Puts what the group sends onto this phone's copy of the card.
///
/// Each phone keeps its own card, so a round still works with no signal and
/// stays in Past Rounds like any other. Rows follow seats: seat 0 is the
/// first row. This phone's own row is only ever changed here on the phone,
/// so a slow update from the group can't undo a score just entered.
struct GroupCard: Equatable {
    static let maxPlayers = 4

    private(set) var names: [String]
    private(set) var grid: StrokeGrid
    let mySeat: Int

    init(names: [String], grid: StrokeGrid, mySeat: Int) {
        self.names = names
        self.grid = grid
        self.mySeat = mySeat
    }

    /// Adds or renames players. A seat past the last row adds rows (named
    /// "Player n" until their name arrives), keeping every score already there.
    mutating func apply(players: [GroupPlayer]) {
        let wanted = min(Self.maxPlayers, max(names.count, (players.map(\.seat).max() ?? -1) + 1))
        if wanted > names.count {
            var values: [Int] = []
            for p in 0..<wanted {
                for hole in 1...StrokeGrid.holeCount {
                    values.append(p < names.count ? grid.strokes(player: p, hole: hole) : 0)
                }
            }
            names += (names.count..<wanted).map { "Player \($0 + 1)" }
            grid = StrokeGrid(playerCount: wanted, values: values)
        }
        for player in players where names.indices.contains(player.seat) && player.seat != mySeat {
            names[player.seat] = player.name
        }
    }

    /// Writes other players' scores. Scores from someone not seated yet, and
    /// this phone's own, are left alone. Returns whether anything changed.
    @discardableResult
    mutating func apply(scores: [GroupScore], players: [GroupPlayer]) -> Bool {
        let seats = Dictionary(players.map { ($0.userID, $0.seat) }, uniquingKeysWith: { first, _ in first })
        var changed = false
        for score in scores {
            guard let seat = seats[score.userID], seat != mySeat, names.indices.contains(seat),
                  (1...StrokeGrid.holeCount).contains(score.hole) else { continue }
            if grid.strokes(player: seat, hole: score.hole) != score.strokes {
                grid.setStrokes(score.strokes, player: seat, hole: score.hole)
                changed = true
            }
        }
        return changed
    }

    /// When this phone joined an existing round (or came back on a new phone),
    /// its own scores already sent fill any hole still empty here.
    mutating func fillMine(from scores: [GroupScore], myUserID: String) {
        for score in scores where score.userID == myUserID && grid.strokes(player: mySeat, hole: score.hole) == 0 {
            grid.setStrokes(score.strokes, player: mySeat, hole: score.hole)
        }
    }

    /// This phone's holes whose score differs from what was last sent.
    static func changedHoles(mine new: StrokeGrid, since sent: [Int: Int], seat: Int) -> [Int: Int] {
        var changed: [Int: Int] = [:]
        for hole in 1...StrokeGrid.holeCount {
            let strokes = new.strokes(player: seat, hole: hole)
            if strokes != (sent[hole] ?? 0) { changed[hole] = strokes }
        }
        return changed
    }
}
