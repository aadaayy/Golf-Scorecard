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

    /// Home instead of a round (launched with -home as well).
    var showsHome = false

    @Environment(CourseLibrary.self) private var library
    @Environment(CourseCatalog.self) private var catalog
    @Environment(GroupSession.self) private var group
    @Environment(\.modelContext) private var modelContext
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
        if showsHome {
            RootView().padding(.top, 24)
        } else if let round {
            VStack(spacing: 0) {
                Text(round.courseName)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .overlay(alignment: .trailing) { OpenLayoutPicker(halves: .duoOpen).padding(.trailing) }
                RoundView(round: round)
            }
            .padding(.top, 24)
        }
    }

    /// A round on the first course with the first hole scored, or with
    /// -mockGroup -groupRound, the pretend friends' group round joined.
    private func makeRound() {
        if !showsHome, round == nil, ProcessInfo.processInfo.arguments.contains("-groupRound") {
            Task {
                round = try? await group.joinRound(code: MockGroupService.joinCode, playerName: "Me", handicap: nil,
                                                   library: library, catalog: catalog, in: modelContext)
            }
            return
        }
        guard !showsHome, round == nil, let course = library.course(id: "pompano-pines") ?? library.courses.first else { return }
        let tee = course.tees.contains("White") ? "White" : course.tees[safe: course.tees.count / 2] ?? ""
        // With -sampleCard, a foursome part way through the back nine, so the
        // full card has scores in both halves.
        let sampleCard = ProcessInfo.processInfo.arguments.contains("-sampleCard")
        let newRound = Round(course: course, tee: tee, players: sampleCard ? ["Alberto", "Sam", "Jo", "Max"] : ["Me"])
        var grid = newRound.grid
        if sampleCard {
            let overPar = [[1, 0, 2, 0, 1, 0, 1, 1, 0, 0, 1, 2, 0],
                           [0, 1, 1, 0, 2, 1, 0, 1, 1, 1, 0, 1, 1],
                           [2, 1, 0, 1, 1, 0, 2, 0, 1, 1, 1, 0, 2],
                           [0, 0, 1, 1, 0, 2, 1, 0, 0, 1, 0, 1, 0]]
            for (player, overs) in overPar.enumerated() {
                for (offset, over) in overs.enumerated() {
                    grid.setStrokes((course.hole(offset + 1)?.par ?? 4) + over, player: player, hole: offset + 1)
                }
            }
        } else {
            grid.setStrokes(6, player: 0, hole: 1)
        }
        newRound.grid = grid
        round = newRound
    }
}
#endif
