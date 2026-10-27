import Foundation
import Observation

/// The courses built into the app, read from the course files at launch.
@Observable
final class CourseLibrary {
    private(set) var courses: [Course] = []

    init(bundle: Bundle = .main) {
        var urls = bundle.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? []
        urls += bundle.urls(forResourcesWithExtension: "json", subdirectory: "Courses") ?? []

        var found: [String: Course] = [:]
        for url in urls {
            guard let data = try? Data(contentsOf: url),
                  let course = try? Course.decode(from: data) else { continue }
            found[course.id] = course
        }
        courses = found.values.sorted { $0.name < $1.name }
    }

    func course(id: String) -> Course? {
        courses.first { $0.id == id }
    }
}
