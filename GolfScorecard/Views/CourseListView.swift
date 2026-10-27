import SwiftUI

/// Screens you can open from the course list besides a course or a round.
enum Screen: Hashable {
    case pastRounds
}

struct CourseListView: View {
    @Environment(CourseLibrary.self) private var library
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section("Courses") {
                    ForEach(library.courses) { course in
                        NavigationLink(value: course) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(course.name).font(.headline)
                                Text(course.town).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityIdentifier("course-\(course.id)")
                    }
                }

                Section {
                    if let url = AppInfo.courseRequestURL {
                        Link(destination: url) {
                            Label("Request a course", systemImage: "envelope")
                        }
                    }
                } footer: {
                    Text("Don't see your course? Send a request and it may be added in a future update.")
                }
            }
            .navigationTitle("Scorecard")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink(value: Screen.pastRounds) {
                        Label("Past Rounds", systemImage: "clock.arrow.circlepath")
                    }
                }
            }
            .navigationDestination(for: Course.self) { course in
                NewRoundView(course: course) { round in
                    // Replace the setup screen with the round, so Back goes to the course list.
                    if !path.isEmpty { path.removeLast() }
                    path.append(round)
                }
            }
            .navigationDestination(for: Round.self) { round in
                RoundView(round: round)
            }
            .navigationDestination(for: Screen.self) { _ in
                PastRoundsView()
            }
        }
    }
}
