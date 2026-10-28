import Foundation

/// The list of courses in the online course library, read from its index.json.
///
/// The library is a public GitHub repository. Each course has a folder with
/// its course.json and one SVG drawing per hole, named after the hole's `map`
/// (for example pompano-pines-01.svg). The index says what's there, so the
/// app can show and search the list before downloading anything.
struct CourseIndex: Codable, Equatable {
    /// Bumped only if the library's layout ever changes in a way older apps can't read.
    var format: Int
    var courses: [Entry]

    static let supportedFormat = 1

    struct Entry: Codable, Identifiable, Hashable {
        var id: String
        var name: String
        var town: String
        var holes: Int
        var par: Int
        var tees: [String]
        /// Total yards from each tee.
        var yards: [String: Int]
        /// Goes up by one each time the course's files change, so phones know to update.
        var version: Int
        /// The course's folder in the library, like "courses/pompano-pines".
        var folder: String
        /// The files in the folder: course.json and the hole drawings.
        var files: [String]
        /// All the files together, for showing the download size.
        var bytes: Int
    }

    static func decode(from data: Data) throws -> CourseIndex {
        try JSONDecoder().decode(CourseIndex.self, from: data)
    }

    /// Courses whose name or town contain every word typed, ignoring case and
    /// accents, sorted by name. An empty search lists every course.
    func search(_ text: String) -> [Entry] {
        let words = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        return courses
            .filter { entry in
                let haystack = "\(entry.name) \(entry.town)"
                return words.allSatisfy { haystack.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
            }
            .sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    func entry(id: String) -> Entry? {
        courses.first { $0.id == id }
    }

    /// Everything wrong with the index, in plain words. Empty means it's good.
    func problems() -> [String] {
        var problems: [String] = []
        if format != Self.supportedFormat {
            problems.append("format \(format) isn't one the app reads (\(Self.supportedFormat))")
        }
        var ids = Set<String>()
        for entry in courses {
            if !ids.insert(entry.id).inserted {
                problems.append("\(entry.id) is listed twice")
            }
            if !Self.isSafeFolder(entry.folder) {
                problems.append("\(entry.id): folder \(entry.folder) isn't a plain folder path")
            }
            if !entry.files.contains(Self.courseFileName) {
                problems.append("\(entry.id): files don't include \(Self.courseFileName)")
            }
            for file in entry.files where !Self.isSafeFileName(file) {
                problems.append("\(entry.id): \(file) isn't a plain file name")
            }
            if entry.version < 1 {
                problems.append("\(entry.id): version must be 1 or more")
            }
        }
        return problems
    }

    static let courseFileName = "course.json"

    /// A file name with no folders in it, so a download can only write inside its own course folder.
    static func isSafeFileName(_ name: String) -> Bool {
        !name.isEmpty && !name.contains("/") && !name.contains("\\") && name != "." && name != ".." && !name.hasPrefix(".")
    }

    /// A relative folder path like "courses/pompano-pines".
    static func isSafeFolder(_ path: String) -> Bool {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        return !path.hasPrefix("/") && !parts.isEmpty && parts.allSatisfy(isSafeFileName)
    }
}

extension CourseIndex.Entry {
    /// True when the library has a newer copy than the one on the phone.
    func isNewer(than installedVersion: Int) -> Bool {
        version > installedVersion
    }

    /// "0.4 MB"
    var sizeText: String {
        let megabytes = Double(bytes) / 1_000_000
        if megabytes < 0.1 { return "0.1 MB" }
        return String(format: "%.1f MB", megabytes)
    }
}
