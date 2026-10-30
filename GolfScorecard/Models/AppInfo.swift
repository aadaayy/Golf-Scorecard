import Foundation

enum AppInfo {
    /// The course library: the course-library folder of this public GitHub
    /// repository, read as plain files. It has to move to a repository of its
    /// own before this one goes private (see README).
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
        return URL(string: "https://raw.githubusercontent.com/aadaayy/Golf-Scorecard/main/course-library/")!
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

    /// The credit the course data's licence (ODbL 1.0) asks for wherever it's shown.
    static let courseDataCredit = "Course data © OpenStreetMap contributors (ODbL 1.0) via OpenGolfAPI. Contains data from OpenGolfAPI (opengolfapi.org)."

    static let openStreetMapCopyrightURL = URL(string: "https://www.openstreetmap.org/copyright")!
}
