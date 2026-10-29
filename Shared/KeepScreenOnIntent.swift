import ActivityKit
import AppIntents
import Foundation

/// The Keep screen on button on the round's Lock Screen card.
///
/// As a `LiveActivityIntent` it runs inside the app, not the extension, so it
/// changes the app's own setting and the open round sees the change at once.
/// A locked phone asks for Face ID before running it.
struct KeepScreenOnIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Keep Screen On During a Round"
    static var description = IntentDescription("Keeps the screen on while a round is open in Yardage Book, or lets it dim again.")

    @Parameter(title: "Keep screen on")
    var on: Bool

    init() {}

    init(on: Bool) {
        self.on = on
    }

    func perform() async throws -> some IntentResult {
        UserDefaults.standard.set(on, forKey: RoundActivityAttributes.keepScreenOnKey)
        for activity in Activity<RoundActivityAttributes>.activities {
            var state = activity.content.state
            state.keepScreenOn = on
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
        return .result()
    }
}
