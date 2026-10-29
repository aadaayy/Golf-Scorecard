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
                .activityBackgroundTint(Book.paper)
                .activitySystemActionForegroundColor(Book.ink)
                .widgetURL(url(context))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("Hole \(context.state.hole)", systemImage: "flag.fill")
                        .font(Book.title(18, relativeTo: .headline))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(context.state.total) · \(context.state.toParText)")
                        .font(Book.mono(17, weight: .semibold))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    KeepScreenOnButton(isOn: context.state.keepScreenOn, onDark: true)
                }
            } compactLeading: {
                Label("\(context.state.hole)", systemImage: "flag.fill")
                    .foregroundStyle(Book.paper)
            } compactTrailing: {
                Text(context.state.toParText).monospacedDigit()
            } minimal: {
                Text("\(context.state.hole)").monospacedDigit()
            }
            .widgetURL(url(context))
            .keylineTint(Book.red)
        }
    }

    private func url(_ context: ActivityViewContext<RoundActivityAttributes>) -> URL {
        RoundActivityAttributes.openURL(roundStart: context.attributes.roundStart, hole: context.state.hole)
    }
}
