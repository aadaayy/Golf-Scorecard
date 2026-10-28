import Foundation

/// A golfer's handicap index, typed in by the golfer. The app never works it out.
///
/// Stored as a number where a plus handicap (better than scratch, written
/// "+1.2") is negative, so net score is always gross minus strokes.
enum HandicapIndex {
    static let range: ClosedRange<Double> = -10...54

    /// Reads "12.4", "12", "12,4" or "+1.2". Nil when empty or out of range.
    static func parse(_ text: String) -> Double? {
        var trimmed = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard !trimmed.isEmpty else { return nil }
        var sign = 1.0
        if trimmed.hasPrefix("+") {
            sign = -1
            trimmed.removeFirst()
        }
        guard let value = Double(trimmed), value >= 0 else { return nil }
        let index = (value * sign * 10).rounded() / 10
        return range.contains(index) ? index : nil
    }

    /// "12.4", "12", or "+1.2" for a plus handicap.
    static func format(_ index: Double) -> String {
        let magnitude = abs(index)
        let number = magnitude == magnitude.rounded() ? String(Int(magnitude)) : String(format: "%.1f", magnitude)
        return index < 0 ? "+\(number)" : number
    }

    /// Strokes the golfer gets: the whole index over 18 holes, half of it over
    /// nine. Nil for any other number of holes, since net only makes sense for
    /// a full round or a full nine. The course's slope isn't on the card, so
    /// the index is used as it is.
    static func strokes(index: Double, holesPlayed: Int) -> Int? {
        switch holesPlayed {
        case 18: Int(index.rounded(.toNearestOrAwayFromZero))
        case 9: Int((index / 2).rounded(.toNearestOrAwayFromZero))
        default: nil
        }
    }
}

/// Names of people the golfer has played with, for quick picks when starting a round.
enum PlayerNames {
    /// Unique names from past rounds, newest round first, leaving out `excluding`
    /// (the golfer's own name) and the "Player N" fill-ins.
    static func recent(from rounds: [[String]], excluding: [String], limit: Int = 6) -> [String] {
        let skip = Set(excluding.map { $0.lowercased() })
        var seen = Set<String>()
        var names: [String] = []
        for players in rounds {
            for name in players {
                let key = name.lowercased()
                guard !name.isEmpty, !skip.contains(key), !seen.contains(key), !isFillIn(name) else { continue }
                seen.insert(key)
                names.append(name)
                if names.count == limit { return names }
            }
        }
        return names
    }

    /// "Player 2" and the like, which the app fills in for blank names.
    static func isFillIn(_ name: String) -> Bool {
        let parts = name.split(separator: " ")
        return parts.count == 2 && parts[0] == "Player" && Int(parts[1]) != nil
    }
}
