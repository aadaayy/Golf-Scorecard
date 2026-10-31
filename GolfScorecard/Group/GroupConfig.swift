import Foundation

/// Where group rounds live: the Supabase project in GroupScoring.plist.
///
/// Only the project URL and its anon (publishable) key, both safe inside the
/// app; the database's row level security decides what each player can do.
struct GroupConfig: Equatable {
    var url: URL
    var key: String
    /// Sign in with Apple, once there's a paid Apple Developer account (README).
    var appleSignIn: Bool

    /// The settings from GroupScoring.plist, or nil while they're still the placeholders.
    static func load(bundle: Bundle = .main) -> GroupConfig? {
        guard let file = bundle.url(forResource: "GroupScoring", withExtension: "plist"),
              let data = try? Data(contentsOf: file),
              let values = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return nil }
        return GroupConfig(values: values)
    }

    init?(values: [String: Any]) {
        guard let text = (values["SupabaseURL"] as? String)?.trimmingCharacters(in: .whitespaces),
              let key = (values["SupabaseAnonKey"] as? String)?.trimmingCharacters(in: .whitespaces),
              !text.contains("YOUR-PROJECT"), !key.isEmpty, !key.hasPrefix("YOUR-"),
              let url = URL(string: text), url.scheme == "https", url.host != nil else { return nil }
        self.init(url: url, key: key, appleSignIn: values["AppleSignIn"] as? Bool ?? false)
    }

    init(url: URL, key: String, appleSignIn: Bool) {
        self.url = url
        self.key = key
        self.appleSignIn = appleSignIn
    }
}
