import SwiftUI
import SwiftData

/// Screens you can open from home besides a course or a round.
enum Screen: Hashable {
    case pastRounds
    case profile
}

/// Where the app opens: a round to pick up again, the courses, past rounds
/// and profile.
///
/// Upright (closed iPhone Duo, regular iPhones) it's one list, and a course
/// opens the start-round screen. Open on the Duo or sideways, the list sits on
/// the left and the picked course is shown on the right, card and all nine
/// holes, with a button to play it.
struct HomeView: View {
    @Environment(CourseLibrary.self) private var library
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @AppStorage(SettingsKey.onboarded) private var onboarded = false
    @AppStorage(SettingsKey.playerName) private var playerName = ""
    @Query(filter: #Predicate<Round> { $0.finishedAt == nil }, sort: \Round.date, order: .reverse)
    private var unfinished: [Round]
    @State private var path = NavigationPath()
    @State private var previewCourseID: String?

    private var isWide: Bool { horizontalSizeClass == .regular || verticalSizeClass == .compact }
    private var previewCourse: Course? {
        previewCourseID.flatMap(library.course(id:)) ?? library.courses.first
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if isWide, let course = previewCourse {
                    WideRoundLayout(card: list, map: CoursePreview(course: course))
                } else {
                    list
                }
            }
            .navigationTitle(playerName.isEmpty ? "Scorecard" : "Hi, \(playerName)")
            .navigationBarTitleDisplayMode(isWide ? .inline : .large)
            .navigationDestination(for: Course.self) { course in
                NewRoundView(course: course) { round in
                    // Replace the setup screen with the round, so Back goes home.
                    if !path.isEmpty { path.removeLast() }
                    path.append(round)
                }
            }
            .navigationDestination(for: Round.self) { round in
                RoundView(round: round)
            }
            .navigationDestination(for: Screen.self) { screen in
                switch screen {
                case .pastRounds: PastRoundsView()
                case .profile: ProfileView { path = NavigationPath() }
                }
            }
        }
        .fullScreenCover(isPresented: Binding(get: { !onboarded }, set: { onboarded = !$0 })) {
            OnboardingView()
        }
    }

    private var list: some View {
        List {
            if let round = unfinished.first {
                Section {
                    Button {
                        path.append(round)
                    } label: {
                        ResumeRow(round: round)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("resume-round")
                }
            }

            Section("Courses") {
                ForEach(library.courses) { course in
                    courseRow(course)
                }
            }

            Section {
                NavigationLink(value: Screen.pastRounds) {
                    Label("Past Rounds", systemImage: "clock.arrow.circlepath")
                }
                .accessibilityIdentifier("past-rounds")
                NavigationLink(value: Screen.profile) {
                    Label("Profile & Settings", systemImage: "person.crop.circle")
                }
                .accessibilityIdentifier("profile")
            }
        }
    }

    @ViewBuilder
    private func courseRow(_ course: Course) -> some View {
        let label = VStack(alignment: .leading, spacing: 2) {
            Text(course.name).font(.headline)
            Text("\(course.town) · \(course.holes.count) holes · Par \(course.par(holes: 1...course.holes.count))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        if isWide {
            // Wide: show the course on the right; its Play button starts the round.
            Button {
                previewCourseID = course.id
            } label: {
                HStack {
                    label
                    Spacer()
                    if course.id == previewCourse?.id {
                        Image(systemName: "chevron.right.circle.fill").foregroundStyle(Color.accentColor)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .listRowBackground(course.id == previewCourse?.id ? Color.accentColor.opacity(0.12) : nil)
            .accessibilityIdentifier("course-\(course.id)")
        } else {
            NavigationLink(value: course) { label }
                .accessibilityIdentifier("course-\(course.id)")
        }
    }
}

/// "Resume round" with where the round stands.
private struct ResumeRow: View {
    let round: Round

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "play.circle.fill")
                .font(.system(size: 34))
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("Resume Round").font(.headline).foregroundStyle(.primary)
                Text(details).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var details: String {
        let hole = round.lastScoredHole
        let whereAt = hole == 0 ? "Not started" : "Thru \(hole)"
        return "\(round.courseName) · \(whereAt) · \(round.date.formatted(.relative(presentation: .named)))"
    }
}

/// A course shown on the right half when the phone is open or sideways: its
/// tees and yardages, all nine holes of a nine, and a button to play it.
struct CoursePreview: View {
    let course: Course
    @AppStorage(SettingsKey.usualTee) private var usualTee = "White"
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var previewHole = 1

    private var tee: String {
        course.tees.contains(usualTee) ? usualTee : course.tees[course.tees.count / 2]
    }

    var body: some View {
        VStack(spacing: 12) {
            // A sideways phone is short, so the holes get the room; the list already names the course.
            if verticalSizeClass != .compact {
                VStack(spacing: 2) {
                    Text(course.name).font(.title2.bold()).multilineTextAlignment(.center)
                    Text(course.town).foregroundStyle(.secondary)
                }
                teeChips
            }
            if !course.backNine.isEmpty {
                Picker("Nine", selection: Binding(get: { previewHole >= 10 }, set: { previewHole = $0 ? 10 : 1 })) {
                    Text("Front 9").tag(false)
                    Text("Back 9").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 280)
            }
            NinePane(course: course, tee: tee, selectedHole: $previewHole)
            NavigationLink(value: course) {
                Label("Play This Course", systemImage: "flag.fill")
                    .font(.headline)
                    .frame(maxWidth: 360)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("play-course")
        }
        .padding()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("course-preview")
    }

    /// Each tee in its card color with its total yards.
    private var teeChips: some View {
        HStack(spacing: 6) {
            ForEach(course.tees, id: \.self) { tee in
                let style = TeeStyle.row(for: tee)
                VStack(spacing: 0) {
                    Text(tee).font(.caption.weight(.semibold))
                    Text("\(course.yards(tee: tee, holes: 1...course.holes.count))")
                        .font(.caption.monospacedDigit())
                }
                .foregroundStyle(style.ink)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(style.band, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(CardColors.edge, lineWidth: 0.5))
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}
