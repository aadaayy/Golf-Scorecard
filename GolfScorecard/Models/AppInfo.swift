import Foundation

enum AppInfo {
    /// The course library: a public GitHub repository read as plain files.
    /// The automatic checks point the app at a copy on the test Mac with
    /// "-courseLibraryURL <url>".
    static var courseLibraryURL: URL {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-courseLibraryURL"), index + 1 < arguments.count,
           let url = URL(string: arguments[index + 1]) {
            return url
        }
        #endif
        return URL(string: "https://raw.githubusercontent.com/aadaayy/golf-course-library/main/")!
    }

    /// Where "Request a course" emails go. Put your support address here before release.
    static let courseRequestEmail = ""

    static var courseRequestURL: URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = courseRequestEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: "Course request"),
            URLQueryItem(name: "body", value: "Course name:\nTown:\n"),
        ]
        return components.url
    }
}
