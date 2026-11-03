import Foundation

/// Quick checks before asking the server, so simple slips get a clear word.
enum EmailCheck {
    /// Supabase's own minimum, unless the project asks for more.
    static let minimumPasswordLength = 6

    static func clean(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Something@something.something, with no spaces.
    static func looksValid(_ email: String) -> Bool {
        let email = clean(email)
        guard !email.contains(" "), let at = email.firstIndex(of: "@") else { return false }
        let name = email[..<at]
        let domain = email[email.index(after: at)...]
        guard !name.isEmpty, let dot = domain.lastIndex(of: "."), !domain.contains("@") else { return false }
        return dot != domain.startIndex && domain.distance(from: dot, to: domain.endIndex) > 2
    }
}
