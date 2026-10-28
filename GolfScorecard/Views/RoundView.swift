import SwiftUI

/// A round in progress: the score card and the hole map.
///
/// Upright phones (closed iPhone Duo, regular iPhones held upright) show one
/// pane at a time with Card and Map tabs. The open Duo (regular width) and any
/// iPhone held sideways (compact height) show two halves, in one of two
/// layouts the golfer picks (see `OpenLayout`).
struct RoundView: View {
    @Bindable var round: Round
    @Environment(CourseLibrary.self) private var library
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @AppStorage(OpenLayout.storageKey) private var openLayout = OpenLayout.nine
    @State private var selectedHole = 1
    @State private var selectedPlayer = 0

    private var isWide: Bool { horizontalSizeClass == .regular || verticalSizeClass == .compact }

    var body: some View {
        Group {
            if let course = library.course(id: round.courseID) {
                content(for: course)
            } else {
                ContentUnavailableView(
                    "Course not found",
                    systemImage: "flag.slash",
                    description: Text("This round's course is no longer in the app.")
                )
            }
        }
        .navigationTitle(round.courseName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isWide {
                ToolbarItem(placement: .topBarTrailing) { OpenLayoutPicker() }
            }
        }
    }

    @ViewBuilder
    private func content(for course: Course) -> some View {
        let card = CardPane(round: round, course: course, selectedHole: $selectedHole, selectedPlayer: $selectedPlayer)
        let map = MapPane(course: course, tee: round.tee, selectedHole: $selectedHole)

        if isWide {
            switch openLayout {
            case .hole:
                WideRoundLayout(card: HoleScorePane(round: round, course: course, selectedHole: $selectedHole), map: map)
            case .nine:
                WideRoundLayout(card: card, map: NinePane(course: course, tee: round.tee, selectedHole: $selectedHole))
            }
        } else {
            TabView {
                card.tabItem { Label("Card", systemImage: "list.number") }
                map.tabItem { Label("Map", systemImage: "map") }
            }
        }
    }
}

/// The two ways to use the open Duo (or a sideways iPhone).
enum OpenLayout: String {
    /// The score for the hole you're on at the left, that hole at the right.
    case hole
    /// The card for the nine you're on at the left, all nine holes at the right.
    case nine

    static let storageKey = "openLayout"
}

/// Switches between the hole view and the nine view. The choice is remembered.
struct OpenLayoutPicker: View {
    @AppStorage(OpenLayout.storageKey) private var layout = OpenLayout.nine

    var body: some View {
        Picker("Layout", selection: $layout) {
            Text("Hole").tag(OpenLayout.hole)
            Text("Nine").tag(OpenLayout.nine)
        }
        .pickerStyle(.segmented)
        .frame(width: 150)
        .accessibilityIdentifier("open-layout")
    }
}

/// Two panes side by side.
///
/// On iPhone Duo, `ArrangementView` moves both panes clear of the fold when
/// the phone is partly folded, and stacks them when the space is taller than
/// wide (laptop pose: map on top, card below). Older SDKs, which can't build
/// `ArrangementView`, get a plain side-by-side layout. The automatic checks
/// set NO_DUO_SDK when their Xcode is older than 27.1.
struct WideRoundLayout<Card: View, Map: View>: View {
    let card: Card
    let map: Map

    var body: some View {
        #if NO_DUO_SDK
        sideBySide
        #else
        if #available(iOS 27.1, *) {
            ArrangementView {
                card
            } secondary: {
                map
            }
            .arrangementViewStyle(.split)
        } else {
            sideBySide
        }
        #endif
    }

    private var sideBySide: some View {
        HStack(spacing: 0) {
            card
            Divider()
            map
        }
    }
}
