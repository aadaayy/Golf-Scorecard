import SwiftUI
import SwiftData

@main
struct GolfScorecardApp: App {
    @State private var library = CourseLibrary()

    /// UI tests launch with this flag so every test starts with no saved rounds.
    private let isUITesting = ProcessInfo.processInfo.arguments.contains("-uiTesting")

    init() {
        // UI tests pick the open layout with "-startLayout hole" or "-startLayout nine".
        // Saved as an ordinary setting so the Hole/Nine switch can still change it.
        let arguments = ProcessInfo.processInfo.arguments
        if isUITesting, let index = arguments.firstIndex(of: "-startLayout"), index + 1 < arguments.count {
            UserDefaults.standard.set(arguments[index + 1], forKey: OpenLayout.storageKey)
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-openDuoPreview") {
                    OpenDuoPreview()
                } else {
                    CourseListView()
                }
                #else
                CourseListView()
                #endif
            }
            .environment(library)
        }
        .modelContainer(for: Round.self, inMemory: isUITesting)
    }
}
