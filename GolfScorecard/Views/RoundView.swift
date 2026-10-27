import SwiftUI

/// A round in progress: the score card and the hole map.
///
/// Closed iPhone Duo and regular iPhones (compact width) show one pane at a
/// time with Card and Map tabs. The open Duo (regular width) shows both,
/// like an unfolded paper card.
struct RoundView: View {
    @Bindable var round: Round
    @Environment(CourseLibrary.self) private var library
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedHole = 1
    @State private var selectedPlayer = 0

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
    }

    @ViewBuilder
    private func content(for course: Course) -> some View {
        let card = CardPane(round: round, course: course, selectedHole: $selectedHole, selectedPlayer: $selectedPlayer)
        let map = MapPane(course: course, tee: round.tee, selectedHole: $selectedHole)

        if horizontalSizeClass == .regular {
            WideRoundLayout(card: card, map: map)
        } else {
            TabView {
                card.tabItem { Label("Card", systemImage: "list.number") }
                map.tabItem { Label("Map", systemImage: "map") }
            }
        }
    }
}

/// Card and map side by side.
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
