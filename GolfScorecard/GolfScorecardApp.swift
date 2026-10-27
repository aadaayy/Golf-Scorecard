import SwiftUI
import SwiftData

@main
struct GolfScorecardApp: App {
    @State private var library = CourseLibrary()

    /// UI tests launch with this flag so every test starts with no saved rounds.
    private let isUITesting = ProcessInfo.processInfo.arguments.contains("-uiTesting")

    var body: some Scene {
        WindowGroup {
            CourseListView()
                .environment(library)
        }
        .modelContainer(for: Round.self, inMemory: isUITesting)
    }
}
