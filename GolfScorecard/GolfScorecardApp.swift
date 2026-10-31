import SwiftUI
import SwiftData

@main
struct GolfScorecardApp: App {
    @State private var library: CourseLibrary
    @State private var catalog = CourseCatalog()
    @State private var group: GroupSession
    private let container: ModelContainer

    /// UI tests launch with this flag so every test starts with no saved rounds
    /// and no settings.
    private static let isUITesting = ProcessInfo.processInfo.arguments.contains("-uiTesting")

    init() {
        Book.styleSystemControls()
        OpenLayout.carryOverOldSetting()
        let arguments = ProcessInfo.processInfo.arguments
        if Self.isUITesting {
            // No downloaded courses left over from an earlier test.
            try? FileManager.default.removeItem(at: CourseLibrary.defaultDownloadsFolder)
        }
        // "-noBuiltInCourses" starts with no courses, so a test can download one.
        _group = State(initialValue: GroupSession.make(arguments: arguments))
        let library = CourseLibrary(includeBuiltIn: !(Self.isUITesting && arguments.contains("-noBuiltInCourses")))
        _library = State(initialValue: library)
        let configuration = ModelConfiguration(isStoredInMemoryOnly: Self.isUITesting)
        container = try! ModelContainer(for: Round.self, configurations: configuration)

        if Self.isUITesting {
            // Fresh every time: the welcome pages show unless a test skips them,
            // and the open layouts come from "-startLayout hole" or "-startLayout nine"
            // (both), "-startDuoOpen ..." or "-startSideways ..." (one), or
            // "-oldLayout ..." (the setting from before the split, to carry over).
            // Saved as ordinary settings so the app can still change them.
            SettingsKey.eraseAll()
            if arguments.contains("-skipOnboarding") {
                UserDefaults.standard.set(true, forKey: SettingsKey.onboarded)
            }
            func value(after flag: String) -> String? {
                guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
                return arguments[index + 1]
            }
            // Not named after the settings themselves: a launch argument with a
            // setting's name would pin it, and the app couldn't change it.
            for (halves, flag) in [(TwoHalves.duoOpen, "-startDuoOpen"), (TwoHalves.sideways, "-startSideways")] {
                if let layout = value(after: flag) ?? value(after: "-startLayout") {
                    UserDefaults.standard.set(layout, forKey: halves.storageKey)
                }
            }
            if let old = value(after: "-oldLayout") {
                UserDefaults.standard.set(old, forKey: OpenLayout.oldStorageKey)
                OpenLayout.carryOverOldSetting()
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
                if ProcessInfo.processInfo.arguments.contains("-lockScreenPreview") {
                    LockScreenCardPreview()
                } else if ProcessInfo.processInfo.arguments.contains("-openDuoPreview") {
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
            .environment(group)
            .bookStyle()
        }
        .modelContainer(container)
    }
}
