import SwiftUI
import SwiftData

@main
struct GolfScorecardApp: App {
    @State private var library: CourseLibrary
    @State private var catalog = CourseCatalog()
    private let container: ModelContainer

    /// UI tests launch with this flag so every test starts with no saved rounds
    /// and no settings.
    private static let isUITesting = ProcessInfo.processInfo.arguments.contains("-uiTesting")

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        if Self.isUITesting {
            // No downloaded courses left over from an earlier test.
            try? FileManager.default.removeItem(at: CourseLibrary.defaultDownloadsFolder)
        }
        // "-noBuiltInCourses" starts with no courses, so a test can download one.
        let library = CourseLibrary(includeBuiltIn: !(Self.isUITesting && arguments.contains("-noBuiltInCourses")))
        _library = State(initialValue: library)
        let configuration = ModelConfiguration(isStoredInMemoryOnly: Self.isUITesting)
        container = try! ModelContainer(for: Round.self, configurations: configuration)

        if Self.isUITesting {
            // Fresh every time: the welcome pages show unless a test skips them,
            // and the open layout comes from "-startLayout hole" or "-startLayout nine".
            // Saved as ordinary settings so the app can still change them.
            SettingsKey.eraseAll()
            if arguments.contains("-skipOnboarding") {
                UserDefaults.standard.set(true, forKey: SettingsKey.onboarded)
            }
            if let index = arguments.firstIndex(of: "-startLayout"), index + 1 < arguments.count {
                UserDefaults.standard.set(arguments[index + 1], forKey: OpenLayout.storageKey)
            }
            #if DEBUG
            if arguments.contains("-sampleRounds") {
                SampleRounds.insert(into: container.mainContext, library: library)
            }
            #endif
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-openDuoPreview") {
                    OpenDuoPreview(showsHome: ProcessInfo.processInfo.arguments.contains("-home"))
                } else {
                    RootView()
                }
                #else
                RootView()
                #endif
            }
            .environment(library)
            .environment(catalog)
        }
        .modelContainer(container)
    }
}
