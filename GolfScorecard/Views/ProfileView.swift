import SwiftUI
import SwiftData

/// The Profile tab: the golfer's name and handicap, how rounds start, and About.
struct ProfileView: View {
    /// Called after Erase Everything, to go back home (where the welcome pages show again).
    var onErase: () -> Void

    @Environment(CourseLibrary.self) private var library
    @Environment(\.modelContext) private var modelContext
    @AppStorage(SettingsKey.playerName) private var playerName = ""
    @AppStorage(SettingsKey.handicap) private var handicap = ""
    @AppStorage(SettingsKey.usualTee) private var usualTee = "White"
    @AppStorage(SettingsKey.keepAwake) private var keepAwake = true
    @AppStorage(OpenLayout.storageKey) private var openLayout = OpenLayout.nine
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var confirmingErase = false

    var body: some View {
        Group {
            if isWide {
                // Open or sideways: you and how you play on the left, About on the right.
                WideRoundLayout(
                    card: Form {
                        youSection
                        playingSection
                    },
                    map: Form {
                        Section {
                            VStack(spacing: 8) {
                                AppMark(size: 72)
                                Text("Scorecard").font(.title2.bold())
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                        }
                        aboutSection
                        eraseSection
                    }
                )
            } else {
                Form {
                    youSection
                    playingSection
                    aboutSection
                    eraseSection
                }
            }
        }
        .navigationTitle("Profile & Settings")
        .navigationBarTitleDisplayMode(isWide ? .inline : .large)
        .confirmationDialog("Erase everything?", isPresented: $confirmingErase, titleVisibility: .visible) {
            Button("Erase Everything", role: .destructive, action: eraseEverything)
        } message: {
            Text("Every round and setting will be deleted. This can't be undone.")
        }
    }

    private var isWide: Bool { horizontalSizeClass == .regular || verticalSizeClass == .compact }

    private var youSection: some View {
        Section {
            LabeledContent {
                TextField("Your name", text: $playerName)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.words)
                    .accessibilityIdentifier("profile-name")
            } label: {
                Label("Name", systemImage: "person")
            }
            LabeledContent {
                TextField("None", text: $handicap)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.numbersAndPunctuation)
                    .accessibilityIdentifier("profile-handicap")
            } label: {
                Label("Handicap", systemImage: "number")
            }
        } header: {
            Text("You")
        } footer: {
            if handicapIsValid {
                Text("Your name goes on the card as the first player. Your handicap is only used for your net score when you finish a round.")
            } else {
                Text("Use a number like 14.2, or +1.5 for a plus handicap.").foregroundStyle(.red)
            }
        }
    }

    private var playingSection: some View {
        Section("Playing") {
            Picker(selection: $usualTee) {
                ForEach(allTees, id: \.self) { Text($0).tag($0) }
            } label: {
                Label("Usual tee", systemImage: "flag")
            }
            Picker(selection: $openLayout) {
                Text("Hole").tag(OpenLayout.hole)
                Text("Nine").tag(OpenLayout.nine)
            } label: {
                Label("Open or sideways", systemImage: "rectangle.split.2x1")
            }
            Toggle(isOn: $keepAwake) {
                Label("Keep screen on during a round", systemImage: "sun.max")
            }
        }
    }

    private var aboutSection: some View {
        Section {
            LabeledContent {
                Text(Self.version)
            } label: {
                Label("Version", systemImage: "info.circle")
            }
            if let url = AppInfo.courseRequestURL, !AppInfo.courseRequestEmail.isEmpty {
                Link(destination: url) {
                    Label("Request a Course", systemImage: "envelope")
                }
            }
        } header: {
            Text("About")
        } footer: {
            Text("Don't see your course in Find Courses? Ask for it and it may be added.")
        }
    }

    private var eraseSection: some View {
        Section {
            Button("Erase Everything", role: .destructive) { confirmingErase = true }
                .accessibilityIdentifier("erase-everything")
        } footer: {
            Text("Deletes every round, setting and downloaded course, and starts the app fresh.")
        }
    }

    /// Every tee across the courses, in card order, so the usual tee can be picked before a round.
    private var allTees: [String] {
        var tees: [String] = []
        for course in library.courses {
            for tee in course.tees where !tees.contains(tee) { tees.append(tee) }
        }
        if !tees.contains(usualTee) { tees.append(usualTee) }
        return tees
    }

    private var handicapIsValid: Bool {
        handicap.trimmingCharacters(in: .whitespaces).isEmpty || HandicapIndex.parse(handicap) != nil
    }

    private func eraseEverything() {
        try? modelContext.delete(model: Round.self)
        try? modelContext.save()
        SettingsKey.eraseAll()
        library.removeAllDownloads()
        onErase()
    }

    static var version: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
