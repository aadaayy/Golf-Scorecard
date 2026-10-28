import Foundation
import Observation

/// The online course library: its list of courses, and downloading one onto
/// the phone. Reads plain files from the library's folder on GitHub,
/// so there's no server, no account and nothing to pay for.
@MainActor
@Observable
final class CourseCatalog {
    enum State: Equatable {
        case notLoaded
        case loading
        case loaded(CourseIndex)
        case failed
    }

    private(set) var state = State.notLoaded
    /// Courses being downloaded right now.
    private(set) var downloading: Set<String> = []
    /// Courses whose last download didn't work, so their row can say so.
    private(set) var failed: Set<String> = []
    let baseURL: URL
    @ObservationIgnored private var checkedForUpdates = false

    init(baseURL: URL = AppInfo.courseLibraryURL) {
        self.baseURL = baseURL
    }

    var index: CourseIndex? {
        if case .loaded(let index) = state { return index }
        return nil
    }

    /// Reads the list of courses. Keeps the last good list while reloading.
    func load() async {
        let previous = index
        if previous == nil { state = .loading }
        do {
            let data = try await fetch(baseURL.appendingPathComponent("index.json"))
            let index = try CourseIndex.decode(from: data)
            guard index.format == CourseIndex.supportedFormat else { throw CatalogError.newerFormat }
            state = .loaded(index)
        } catch {
            state = previous.map { .loaded($0) } ?? .failed
        }
    }

    /// Downloads a course, checks every file, and only then puts it on the phone,
    /// so a dropped signal never leaves half a course behind.
    func download(_ entry: CourseIndex.Entry, into library: CourseLibrary) async {
        guard !downloading.contains(entry.id) else { return }
        downloading.insert(entry.id)
        failed.remove(entry.id)
        defer { downloading.remove(entry.id) }

        let manager = FileManager.default
        let folder = manager.temporaryDirectory.appendingPathComponent("course-\(UUID().uuidString)", isDirectory: true)
        do {
            guard CourseIndex.isSafeFolder(entry.folder),
                  entry.files.allSatisfy(CourseIndex.isSafeFileName),
                  entry.files.contains(CourseIndex.courseFileName) else { throw CatalogError.badEntry }
            try manager.createDirectory(at: folder, withIntermediateDirectories: true)
            var remote = baseURL
            for part in entry.folder.split(separator: "/") {
                remote = remote.appendingPathComponent(String(part), isDirectory: true)
            }
            for file in entry.files {
                let data = try await fetch(remote.appendingPathComponent(file))
                try data.write(to: folder.appendingPathComponent(file))
            }

            let course = try Course.decode(from: Data(contentsOf: folder.appendingPathComponent(CourseIndex.courseFileName)))
            guard course.id == entry.id, course.problems().isEmpty else { throw CatalogError.badCourse }
            for name in course.holes.compactMap(\.map) {
                // Every drawing must be there and readable.
                _ = try HoleSketch.parse(Data(contentsOf: folder.appendingPathComponent("\(name).svg")))
            }
            try library.install(course, from: folder)
        } catch {
            try? manager.removeItem(at: folder)
            failed.insert(entry.id)
        }
    }

    /// Once per launch, quietly brings every course on the phone up to the
    /// library's newest version. Does nothing without a signal.
    func updateCourses(in library: CourseLibrary) async {
        guard !checkedForUpdates else { return }
        checkedForUpdates = true
        await load()
        guard let index else { return }
        for entry in index.courses {
            if let installed = library.installedVersion(of: entry.id), entry.isNewer(than: installed) {
                await download(entry, into: library)
            }
        }
    }

    private func fetch(_ url: URL) async throws -> Data {
        // Always ask for the newest copy, so a course fixed in the library shows up straight away.
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw CatalogError.notFound
        }
        return data
    }

    enum CatalogError: Error {
        case newerFormat, badEntry, badCourse, notFound
    }
}
