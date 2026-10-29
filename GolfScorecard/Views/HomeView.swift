import SwiftUI
import SwiftData

/// The Play tab: a round to pick up again, the courses on the phone, and
/// Find Courses to download more from the course library.
///
/// Upright (closed iPhone Duo, regular iPhones) it's one list, and a course
/// opens the start-round screen. Open on the Duo or sideways, the list sits on
/// the left and the picked course is shown on the right, card and all nine
/// holes, with a button to play it.
struct HomeView: View {
    @Environment(CourseLibrary.self) private var library
    @Environment(CourseCatalog.self) private var catalog
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @AppStorage(SettingsKey.playerName) private var playerName = ""
    @Query(filter: #Predicate<Round> { $0.finishedAt == nil }, sort: \Round.date, order: .reverse)
    private var unfinished: [Round]
    @Environment(\.openRound) private var openRound
    @State private var path = NavigationPath()
    @State private var previewCourseID: String?
    @State private var removing: Course?

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
            .navigationTitle(playerName.isEmpty ? "Yardage Book" : "Hi, \(playerName)")
            .navigationBarTitleDisplayMode(isWide ? .inline : .large)
            .navigationDestination(for: Course.self) { course in
                NewRoundView(course: course) { round in
                    // Leave the setup screen behind, so closing the round comes back home.
                    path = NavigationPath()
                    openRound(round)
                }
            }
            .navigationDestination(for: HomeRoute.self) { _ in
                FindCoursesView()
            }
            .confirmationDialog(
                "Remove \(removing?.name ?? "this course")?",
                isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                titleVisibility: .visible,
                presenting: removing
            ) { course in
                Button("Remove Course", role: .destructive) {
                    library.remove(course.id)
                }
            } message: { _ in
                Text("Past rounds stay. You can download it again from Find Courses.")
            }
        }
        .task {
            // Courses fixed in the library reach the phone on their own.
            await catalog.updateCourses(in: library)
        }
    }

    private var list: some View {
        List {
            if let round = unfinished.first {
                Section {
                    Button {
                        openRound(round)
                    } label: {
                        ResumeRow(round: round)
                    }
                    .buttonStyle(.plain)
                    .bookRow()
                    .accessibilityIdentifier("resume-round")
                }
            }

            Section {
                ForEach(library.courses) { course in
                    courseRow(course)
                        .swipeActions {
                            if library.isDownloaded(course.id) {
                                Button("Remove", systemImage: "trash", role: .destructive) {
                                    removing = course
                                }
                            }
                        }
                }
                NavigationLink(value: HomeRoute.findCourses) {
                    Label("Find Courses", systemImage: "magnifyingglass")
                        .font(.headline)
                }
                .bookRow()
                .accessibilityIdentifier("find-courses")
            } header: {
                Text("Courses")
            } footer: {
                if library.courses.isEmpty {
                    Text("Find your course and download it to start playing.")
                }
            }
        }
        .bookList()
    }

    @ViewBuilder
    private func courseRow(_ course: Course) -> some View {
        let label = VStack(alignment: .leading, spacing: 2) {
            Text(course.name).font(Book.title(18, relativeTo: .headline))
            Text("\(course.town) · \(course.holes.count) holes · Par \(course.par(holes: 1...course.holes.count))")
                .font(.subheadline)
                .foregroundStyle(Book.pencil)
            if library.isDownloaded(course.id) {
                Label("Downloaded", systemImage: "arrow.down.circle.fill")
                    .font(.caption)
                    .foregroundStyle(Book.leaf)
            }
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
                        Image(systemName: "chevron.right.circle.fill").foregroundStyle(Book.red)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .bookRow(marked: course.id == previewCourse?.id)
            .accessibilityIdentifier("course-\(course.id)")
        } else {
            NavigationLink(value: course) { label }
                .bookRow()
                .accessibilityIdentifier("course-\(course.id)")
        }
    }
}

/// Screens pushed from Play, besides starting a round.
enum HomeRoute: Hashable {
    case findCourses
}

/// "Resume round" with where the round stands.
private struct ResumeRow: View {
    let round: Round

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "play.circle.fill")
                .font(.system(size: 34))
                .foregroundStyle(Book.red)
            VStack(alignment: .leading, spacing: 2) {
                Text("Resume Round").font(Book.title(18, relativeTo: .headline)).foregroundStyle(Book.ink)
                Text(details).font(.subheadline).foregroundStyle(Book.pencil)
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
        Group {
            if verticalSizeClass == .compact {
                // A sideways phone is short, so the holes get the height: the
                // nine switch and Play share one row, and the list already
                // names the course.
                VStack(spacing: 8) {
                    HStack(spacing: 12) {
                        ninePicker
                        playButton
                    }
                    NinePane(course: course, tee: tee, selectedHole: $previewHole, showsHeader: false, identifier: "preview-nine-pane")
                }
            } else {
                VStack(spacing: 12) {
                    VStack(spacing: 2) {
                        Text(course.name).font(Book.title(24, relativeTo: .title2)).multilineTextAlignment(.center)
                        Text(course.town).foregroundStyle(Book.pencil)
                    }
                    teeChips
                    ninePicker.frame(maxWidth: 280)
                    NinePane(course: course, tee: tee, selectedHole: $previewHole, identifier: "preview-nine-pane")
                    playButton
                }
            }
        }
        .padding()
        .paperBackground()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("course-preview")
    }

    @ViewBuilder
    private var ninePicker: some View {
        if !course.backNine.isEmpty {
            Picker("Nine", selection: Binding(get: { previewHole >= 10 }, set: { previewHole = $0 ? 10 : 1 })) {
                Text("Front 9").tag(false)
                Text("Back 9").tag(true)
            }
            .pickerStyle(.segmented)
        }
    }

    private var playButton: some View {
        NavigationLink(value: course) {
            Label(verticalSizeClass == .compact ? "Play" : "Play This Course", systemImage: "figure.golf")
                .font(.headline)
                .frame(maxWidth: 360)
                .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .foregroundStyle(Book.paper)
        .accessibilityIdentifier("play-course")
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
