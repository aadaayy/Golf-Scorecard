import ActivityKit
import SwiftUI
import WidgetKit

@main
struct RoundActivityBundle: WidgetBundle {
    var body: some Widget {
        RoundLiveActivity()
    }
}

/// The round being played, on the Lock Screen and in the Dynamic Island.
/// The app starts, updates and ends it (see LiveRound in the app).
struct RoundLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RoundActivityAttributes.self) { context in
            RoundActivityView(courseName: context.attributes.courseName, state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.55))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(url(context))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("Hole \(context.state.hole)", systemImage: "flag.fill")
                        .font(.headline)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(context.state.total) · \(context.state.toParText)")
                        .font(.headline.monospacedDigit())
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Toggle(isOn: context.state.keepScreenOn, intent: KeepScreenOnIntent(on: !context.state.keepScreenOn)) {
                        Label("Keep screen on", systemImage: "sun.max")
                    }
                    .toggleStyle(.switch)
                }
            } compactLeading: {
                Label("\(context.state.hole)", systemImage: "flag.fill")
            } compactTrailing: {
                Text(context.state.toParText).monospacedDigit()
            } minimal: {
                Text("\(context.state.hole)").monospacedDigit()
            }
            .widgetURL(url(context))
        }
    }

    private func url(_ context: ActivityViewContext<RoundActivityAttributes>) -> URL {
        RoundActivityAttributes.openURL(roundStart: context.attributes.roundStart, hole: context.state.hole)
    }
}
