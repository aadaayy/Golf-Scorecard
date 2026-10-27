import Foundation

enum AppInfo {
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
