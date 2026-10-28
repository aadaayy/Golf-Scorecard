import SwiftUI
import SwiftData

/// The golfer's name and handicap, how rounds start, and About.
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
    @State private var confirmingErase = false

    var body: some View {
        Form {
            Section {
                LabeledContent("Name") {
                    TextField("Your name", text: $playerName)
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.words)
                        .accessibilityIdentifier("profile-name")
                }
                LabeledContent("Handicap") {
                    TextField("None", text: $handicap)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.numbersAndPunctuation)
                        .accessibilityIdentifier("profile-handicap")
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

            Section("Playing") {
                Picker("Usual tee", selection: $usualTee) {
                    ForEach(allTees, id: \.self) { Text($0).tag($0) }
                }
                Picker("Open or sideways", selection: $openLayout) {
                    Text("Hole").tag(OpenLayout.hole)
                    Text("Nine").tag(OpenLayout.nine)
                }
                Toggle("Keep screen on during a round", isOn: $keepAwake)
            }

            Section {
                LabeledContent("Version", value: Self.version)
                if let url = AppInfo.courseRequestURL, !AppInfo.courseRequestEmail.isEmpty {
                    Link(destination: url) {
                        Label("Request a Course", systemImage: "envelope")
                    }
                }
            } header: {
                Text("About")
            } footer: {
                Text("Don't see your course? Ask for it and it may come in a future update.")
            }

            Section {
                Button("Erase Everything", role: .destructive) { confirmingErase = true }
                    .accessibilityIdentifier("erase-everything")
            } footer: {
                Text("Deletes every round and setting, and starts the app fresh.")
            }
        }
        .navigationTitle("Profile & Settings")
        .confirmationDialog("Erase everything?", isPresented: $confirmingErase, titleVisibility: .visible) {
            Button("Erase Everything", role: .destructive, action: eraseEverything)
        } message: {
            Text("Every round and setting will be deleted. This can't be undone.")
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
        onErase()
    }

    static var version: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
