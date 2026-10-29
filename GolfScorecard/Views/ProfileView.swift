import ActivityKit
import SwiftUI
import SwiftData

/// The Profile tab, laid out like the iPhone's Settings: you at the top, then
/// Playing, During a Round, History and About.
///
/// Open on the Duo or sideways, the sections sit on the left and the chosen
/// one's settings on the right, where changes are made. Upright (closed Duo,
/// regular iPhones) it's one list, and a section opens its own page.
struct ProfileView: View {
    /// Called after Erase Everything, to go back home (where the welcome pages show again).
    var onErase: () -> Void
    /// Switches to the Past Rounds tab.
    var onShowPastRounds: () -> Void = {}

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @AppStorage(SettingsKey.playerName) private var playerName = ""
    @AppStorage(SettingsKey.handicap) private var handicap = ""
    @State private var picked = ProfileSection.profile

    private var isWide: Bool { horizontalSizeClass == .regular || verticalSizeClass == .compact }

    var body: some View {
        Group {
            if isWide {
                WideRoundLayout(card: sectionList, map: widePage)
            } else {
                sectionList
                    .navigationDestination(for: ProfileSection.self) { section in
                        page(section)
                            .navigationTitle(section.title)
                            .navigationBarTitleDisplayMode(.inline)
                    }
            }
        }
        .navigationTitle("Profile & Settings")
        .navigationBarTitleDisplayMode(isWide ? .inline : .large)
    }

    /// You at the top, then a row for each section.
    private var sectionList: some View {
        List {
            Section {
                row(.profile) { profileHeader }
            }
            Section {
                ForEach(ProfileSection.allCases.filter { $0 != .profile }) { section in
                    row(section) {
                        Label {
                            Text(section.title)
                        } icon: {
                            SectionIcon(section: section)
                        }
                    }
                }
            }
        }
        .modifier(ExtraSideMargins(isOn: isWide, amount: 24))
        .accessibilityIdentifier("profile-sections")
    }

    /// Open or sideways a row picks what shows on the right; upright it opens a page.
    @ViewBuilder
    private func row<Content: View>(_ section: ProfileSection, @ViewBuilder content: () -> Content) -> some View {
        if isWide {
            Button {
                picked = section
            } label: {
                HStack {
                    content()
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .listRowBackground(picked == section ? Color.accentColor.opacity(0.18) : nil)
            .accessibilityAddTraits(picked == section ? .isSelected : [])
            .accessibilityIdentifier("profile-section-\(section.rawValue)")
        } else {
            NavigationLink(value: section) {
                content()
            }
            .accessibilityIdentifier("profile-section-\(section.rawValue)")
        }
    }

    private var profileHeader: some View {
        HStack(spacing: 14) {
            Text(initials)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Color(red: 0.18, green: 0.49, blue: 0.24), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(playerName.isEmpty ? "Your name" : playerName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(playerName.isEmpty ? .secondary : .primary)
                Text(handicapLine).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var initials: String {
        let letters = playerName.split(separator: " ").prefix(2).compactMap(\.first)
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }

    private var handicapLine: String {
        let typed = handicap.trimmingCharacters(in: .whitespaces)
        return typed.isEmpty ? "Name and handicap" : "Handicap \(typed)"
    }

    /// The right half when open or sideways: the picked section, with its name on top.
    private var widePage: some View {
        page(picked)
            .safeAreaInset(edge: .top, spacing: 0) {
                Text(picked.title)
                    .font(.title2.bold())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 32)
                    .padding(.top, 12)
                    .padding(.bottom, 4)
                    .background(Color(.systemGroupedBackground))
                    .accessibilityIdentifier("profile-page-title")
            }
            .id(picked)
    }

    @ViewBuilder
    private func page(_ section: ProfileSection) -> some View {
        Group {
            switch section {
            case .profile: MyProfilePage()
            case .playing: PlayingPage()
            case .round: DuringRoundPage()
            case .history: HistoryPage(onShowPastRounds: onShowPastRounds)
            case .about: AboutPage(onErase: onErase)
            }
        }
        .modifier(ExtraSideMargins(isOn: isWide, amount: 24))
    }
}

enum ProfileSection: String, CaseIterable, Identifiable, Hashable {
    case profile, playing, round, history, about

    var id: Self { self }

    var title: String {
        switch self {
        case .profile: "My Profile"
        case .playing: "Playing"
        case .round: "During a Round"
        case .history: "History"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .profile: "person.fill"
        case .playing: "flag.fill"
        case .round: "lock.iphone"
        case .history: "clock.arrow.circlepath"
        case .about: "info"
        }
    }

    var color: Color {
        switch self {
        case .profile: Color(red: 0.18, green: 0.49, blue: 0.24)
        case .playing: .green
        case .round: .orange
        case .history: .blue
        case .about: .gray
        }
    }
}

/// Room at the sides of each half when open or sideways, so the two halves'
/// boxes don't run into each other at the middle.
private struct ExtraSideMargins: ViewModifier {
    let isOn: Bool
    let amount: CGFloat

    func body(content: Content) -> some View {
        if isOn {
            content.contentMargins(.horizontal, amount, for: .scrollContent)
        } else {
            content
        }
    }
}

/// A white symbol on a small colored square, like the iPhone's Settings.
private struct SectionIcon: View {
    let section: ProfileSection

    var body: some View {
        Image(systemName: section.symbol)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(section.color, in: RoundedRectangle(cornerRadius: 7))
    }
}

/// Name and handicap.
private struct MyProfilePage: View {
    @AppStorage(SettingsKey.playerName) private var playerName = ""
    @AppStorage(SettingsKey.handicap) private var handicap = ""

    var body: some View {
        Form {
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
            } footer: {
                if handicapIsValid {
                    Text("Your name goes on the card as the first player. Your handicap is only used for your net score when you finish a round.")
                } else {
                    Text("Use a number like 14.2, or +1.5 for a plus handicap.").foregroundStyle(.red)
                }
            }
        }
    }

    private var handicapIsValid: Bool {
        handicap.trimmingCharacters(in: .whitespaces).isEmpty || HandicapIndex.parse(handicap) != nil
    }
}

/// How rounds start: the usual tee, and the open view.
private struct PlayingPage: View {
    @Environment(CourseLibrary.self) private var library
    @AppStorage(SettingsKey.usualTee) private var usualTee = "White"
    @AppStorage(OpenLayout.storageKey) private var openLayout = OpenLayout.nine

    var body: some View {
        Form {
            Section {
                Picker(selection: $usualTee) {
                    ForEach(allTees, id: \.self) { Text($0).tag($0) }
                } label: {
                    Label("Usual tee", systemImage: "flag")
                }
            } footer: {
                Text("Picked first when you start a round, if the course has it.")
            }
            Section {
                Picker(selection: $openLayout) {
                    Text("Hole").tag(OpenLayout.hole)
                    Text("Nine").tag(OpenLayout.nine)
                } label: {
                    Label("Open or sideways", systemImage: "rectangle.split.2x1")
                }
            } footer: {
                Text("With the Duo open or the phone sideways, Hole shows your score beside the hole you're on, and Nine shows the card beside all nine holes. You can switch during a round too.")
            }
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
}

/// The round's Lock Screen card and keeping the screen on.
private struct DuringRoundPage: View {
    @AppStorage(SettingsKey.showOnLockScreen) private var showOnLockScreen = true
    @AppStorage(SettingsKey.keepAwake) private var keepAwake = false

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $showOnLockScreen) {
                    Label("Show round on Lock Screen", systemImage: "lock.iphone")
                }
                .accessibilityIdentifier("profile-lock-screen")
            } footer: {
                if ActivityAuthorizationInfo().areActivitiesEnabled {
                    Text("The hole you're on and your score stay on the Lock Screen during a round. Tap it to go straight back to that hole.")
                } else {
                    Text("Live Activities are turned off for Scorecard. Turn them on in the iPhone's Settings app, under Scorecard.")
                }
            }
            Section {
                Toggle(isOn: $keepAwake) {
                    Label("Keep screen on", systemImage: "sun.max")
                }
                .accessibilityIdentifier("profile-keep-awake")
            } footer: {
                Text("Stops the screen dimming while a round is open. It uses more battery, so it's off unless you turn it on, here or on the round's Lock Screen card.")
            }
        }
        .onChange(of: showOnLockScreen) {
            if !showOnLockScreen { LiveRound.end() }
        }
    }
}

/// Totals across the rounds on this phone, and the way to Past Rounds.
private struct HistoryPage: View {
    var onShowPastRounds: () -> Void
    @Query(sort: \Round.date, order: .reverse) private var rounds: [Round]

    var body: some View {
        Form {
            Section {
                LabeledContent("Rounds finished", value: "\(finished.count)")
                LabeledContent("Rounds in progress", value: "\(rounds.count - finished.count)")
                LabeledContent("Best 18 holes", value: best(holes: 18).map { "\($0)" } ?? "None yet")
                LabeledContent("Best 9 holes", value: best(holes: 9).map { "\($0)" } ?? "None yet")
            } footer: {
                Text("Your own scores, from rounds on this phone.")
            }
            Section {
                Button {
                    onShowPastRounds()
                } label: {
                    Label("See Past Rounds", systemImage: "clock.arrow.circlepath")
                }
                .accessibilityIdentifier("profile-past-rounds")
            }
        }
    }

    private var finished: [Round] { rounds.filter(\.isFinished) }

    /// The lowest total among finished rounds with exactly this many holes scored.
    private func best(holes: Int) -> Int? {
        finished.compactMap { round in
            let grid = round.grid
            let all = 1...StrokeGrid.holeCount
            return grid.holesPlayed(player: 0, holes: all) == holes ? grid.total(player: 0, holes: all) : nil
        }
        .min()
    }
}

/// The app, its version, asking for a course, and Erase Everything.
private struct AboutPage: View {
    var onErase: () -> Void
    @Environment(CourseLibrary.self) private var library
    @Environment(\.modelContext) private var modelContext
    @State private var confirmingErase = false

    var body: some View {
        Form {
            Section {
                VStack(spacing: 8) {
                    AppMark(size: 64)
                    Text("Scorecard").font(.title3.bold())
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
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
            } footer: {
                Text("Don't see your course in Find Courses? Ask for it and it may be added.")
            }
            Section {
                Button("Erase Everything", role: .destructive) { confirmingErase = true }
                    .accessibilityIdentifier("erase-everything")
            } footer: {
                Text("Deletes every round, setting and downloaded course, and starts the app fresh.")
            }
        }
        .confirmationDialog("Erase everything?", isPresented: $confirmingErase, titleVisibility: .visible) {
            Button("Erase Everything", role: .destructive, action: eraseEverything)
        } message: {
            Text("Every round and setting will be deleted. This can't be undone.")
        }
    }

    private func eraseEverything() {
        LiveRound.end()
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
