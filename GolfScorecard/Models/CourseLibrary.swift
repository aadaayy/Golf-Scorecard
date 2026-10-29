import Foundation
import UIKit
import Observation

/// The courses on this phone: the ones built into the app, read from the
/// course files at launch, and the ones downloaded from the course library.
///
/// Downloaded courses live in Application Support, one folder each with its
/// course.json and hole drawings, so they work with no signal. A downloaded
/// copy of a built-in course (a newer version of it) is used in its place.
@Observable
final class CourseLibrary {
    private(set) var courses: [Course] = []
    private var builtIn: [String: Course] = [:]
    private var downloaded: [String: Course] = [:]
    let downloadsFolder: URL

    static var defaultDownloadsFolder: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Downloaded Courses", isDirectory: true)
    }

    /// - Parameter includeBuiltIn: false leaves out the built-in courses, so the
    ///   automatic checks can start with none and download one.
    init(bundle: Bundle = .main, includeBuiltIn: Bool = true, downloadsFolder: URL = CourseLibrary.defaultDownloadsFolder) {
        self.downloadsFolder = downloadsFolder
        if includeBuiltIn {
            var urls = bundle.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? []
            urls += bundle.urls(forResourcesWithExtension: "json", subdirectory: "Courses") ?? []
            for url in urls {
                guard let data = try? Data(contentsOf: url),
                      let course = try? Course.decode(from: data) else { continue }
                builtIn[course.id] = course
            }
        }
        loadDownloads()
    }

    func course(id: String) -> Course? {
        courses.first { $0.id == id }
    }

    /// True when the course came from the course library, so it can be removed.
    func isDownloaded(_ id: String) -> Bool {
        downloaded[id] != nil
    }

    /// The version on the phone, or nil when the course isn't on the phone.
    func installedVersion(of id: String) -> Int? {
        course(id: id)?.currentVersion
    }

    /// Moves a downloaded course's checked files into place, replacing an older copy.
    func install(_ course: Course, from folder: URL) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: downloadsFolder, withIntermediateDirectories: true)
        let destination = courseFolder(course.id)
        if manager.fileExists(atPath: destination.path) {
            _ = try manager.replaceItemAt(destination, withItemAt: folder)
        } else {
            try manager.moveItem(at: folder, to: destination)
        }
        HoleSketches.shared.forget(course: downloaded[course.id])
        downloaded[course.id] = course
        HoleSketches.shared.register(course, in: destination)
        refresh()
    }

    /// Deletes a downloaded course. A built-in course comes back in its place.
    func remove(_ id: String) {
        try? FileManager.default.removeItem(at: courseFolder(id))
        HoleSketches.shared.forget(course: downloaded[id])
        downloaded[id] = nil
        refresh()
    }

    func removeAllDownloads() {
        for id in Array(downloaded.keys) { remove(id) }
        try? FileManager.default.removeItem(at: downloadsFolder)
    }

    private func courseFolder(_ id: String) -> URL {
        downloadsFolder.appendingPathComponent(id, isDirectory: true)
    }

    private func loadDownloads() {
        let folders = (try? FileManager.default.contentsOfDirectory(at: downloadsFolder, includingPropertiesForKeys: nil)) ?? []
        for folder in folders {
            let file = folder.appendingPathComponent(CourseIndex.courseFileName)
            guard let data = try? Data(contentsOf: file),
                  let course = try? Course.decode(from: data),
                  course.id == folder.lastPathComponent else { continue }
            downloaded[course.id] = course
            HoleSketches.shared.register(course, in: folder)
        }
        refresh()
    }

    private func refresh() {
        courses = builtIn.merging(downloaded) { _, download in download }
            .values
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

/// The hole drawings, found by the hole's `map` name: downloaded courses'
/// from their folders, built-in courses' from the asset catalog (kept there
/// as data, so the app can read the shapes and draw them its own way).
final class HoleSketches: @unchecked Sendable {
    static let shared = HoleSketches()

    private let lock = NSLock()
    private var files: [String: URL] = [:]
    private var cache: [String: HoleSketch] = [:]
    private var plans: [String: HolePlan] = [:]

    func register(_ course: Course, in folder: URL) {
        lock.lock()
        defer { lock.unlock() }
        for name in course.holes.compactMap(\.map) {
            files[name] = folder.appendingPathComponent("\(name).svg")
            cache[name] = nil
            plans[name] = nil
        }
    }

    func forget(course: Course?) {
        guard let course else { return }
        lock.lock()
        defer { lock.unlock() }
        for name in course.holes.compactMap(\.map) {
            files[name] = nil
            cache[name] = nil
            plans[name] = nil
        }
    }

    /// The drawing, read the first time it's asked for. A downloaded copy
    /// wins over the built-in one, since it's the newer.
    func sketch(named name: String) -> HoleSketch? {
        lock.lock()
        defer { lock.unlock() }
        return loadSketch(named: name)
    }

    /// The drawing read as a yardage book page: rough, green, line of play, trees.
    func plan(named name: String) -> HolePlan? {
        lock.lock()
        defer { lock.unlock() }
        if let plan = plans[name] { return plan }
        guard let sketch = loadSketch(named: name) else { return nil }
        let plan = HolePlan(sketch: sketch)
        plans[name] = plan
        return plan
    }

    /// Call with the lock held.
    private func loadSketch(named name: String) -> HoleSketch? {
        if let sketch = cache[name] { return sketch }
        let data: Data?
        if let file = files[name] {
            data = try? Data(contentsOf: file)
        } else {
            data = NSDataAsset(name: name)?.data
        }
        guard let data, let sketch = try? HoleSketch.parse(data) else { return nil }
        cache[name] = sketch
        return sketch
    }
}
