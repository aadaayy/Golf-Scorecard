import Foundation

/// The two ways to use the two halves a round gets when the Duo is open or a
/// phone is turned sideways.
enum OpenLayout: String, CaseIterable {
    /// The score for the hole you're on at the left, that hole at the right.
    case hole
    /// The card for the nine you're on at the left, all nine holes at the right.
    case nine

    /// What both the open Duo and a sideways phone start on.
    static let standard = OpenLayout.hole

    /// The one setting that used to cover both the open Duo and a sideways
    /// phone, before each had its own.
    static let oldStorageKey = "openLayout"

    /// Carries a layout picked before the split over to both new settings, so
    /// nobody loses their pick. Settings already made separately are kept.
    static func carryOverOldSetting(in defaults: UserDefaults = .standard) {
        guard let old = defaults.string(forKey: oldStorageKey) else { return }
        if OpenLayout(rawValue: old) != nil {
            for halves in TwoHalves.allCases where defaults.object(forKey: halves.storageKey) == nil {
                defaults.set(old, forKey: halves.storageKey)
            }
        }
        defaults.removeObject(forKey: oldStorageKey)
    }
}

/// When a round shows two halves. Each remembers its own `OpenLayout`, so the
/// open Duo and a sideways phone can each start the way the golfer likes.
enum TwoHalves: String, CaseIterable {
    /// The iPhone Duo opened up (regular width and height).
    case duoOpen
    /// Any iPhone turned on its side, the closed Duo included (compact height).
    case sideways

    var storageKey: String {
        switch self {
        case .duoOpen: "duoOpenLayout"
        case .sideways: "sidewaysLayout"
        }
    }

    /// The name on Profile and the welcome pages.
    var title: String {
        switch self {
        case .duoOpen: "Duo open"
        case .sideways: "Sideways"
        }
    }
}
