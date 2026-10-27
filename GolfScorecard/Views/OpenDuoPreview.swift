#if DEBUG
import SwiftUI

/// A round drawn at the size of the open iPhone Duo's screen, shrunk to fit
/// whatever simulator runs it. The automatic checks can't unfold the Duo
/// simulator, so they screenshot this to show the open layout.
///
/// The size, about 951 by 669 points, comes from a screenshot taken on an
/// open Duo. Shown only when the app is launched with -openDuoPreview.
struct OpenDuoPreview: View {
    static let openScreen = CGSize(width: 951, height: 669)

    @Environment(CourseLibrary.self) private var library
    @State private var round: Round?

    var body: some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width / Self.openScreen.width, geometry.size.height / Self.openScreen.height)
            screen
                .frame(width: Self.openScreen.width, height: Self.openScreen.height)
                .background(Color(.systemBackground))
                .environment(\.horizontalSizeClass, .regular)
                .environment(\.verticalSizeClass, .regular)
                .scaleEffect(scale)
                .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .background(Color.black)
        .ignoresSafeArea()
        .onAppear(perform: makeRound)
    }

    @ViewBuilder
    private var screen: some View {
        if let round {
            VStack(spacing: 0) {
                Text(round.courseName)
                    .font(.headline)
                    .frame(height: 44)
                RoundView(round: round)
            }
            .padding(.top, 24)
        }
    }

    /// A round on the first course with the first hole scored.
    private func makeRound() {
        guard round == nil, let course = library.course(id: "pompano-pines") ?? library.courses.first else { return }
        let tee = course.tees.contains("White") ? "White" : course.tees[course.tees.count / 2]
        let newRound = Round(course: course, tee: tee, players: ["Me"])
        var grid = newRound.grid
        grid.setStrokes(6, player: 0, hole: 1)
        newRound.grid = grid
        round = newRound
    }
}
#endif
