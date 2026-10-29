import AppIntents
import SwiftUI

/// The round's Lock Screen card: the hole you're on, your score, and a
/// switch to keep the screen on. Tapping anywhere else opens the round at
/// this hole.
struct RoundActivityView: View {
    let courseName: String
    let state: RoundActivityAttributes.ContentState

    private static let green = Color(red: 0.30, green: 0.69, blue: 0.36)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "flag.fill").foregroundStyle(Self.green)
                Text(courseName).lineLimit(1)
                Spacer(minLength: 8)
                Text(state.thru == 0 ? "Not started" : "Thru \(state.thru)")
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline.weight(.semibold))

            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Hole \(state.hole)").font(.title2.bold())
                    if let par = state.par {
                        Text("Par \(par)").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                score(state.strokes > 0 ? "\(state.strokes)" : "–", caption: "This hole")
                score("\(state.total)", caption: state.thru == 0 ? "Total" : "Total \(state.toParText)")
                    .padding(.leading, 18)
            }

            Toggle(isOn: state.keepScreenOn, intent: KeepScreenOnIntent(on: !state.keepScreenOn)) {
                Label("Keep screen on", systemImage: state.keepScreenOn ? "sun.max.fill" : "sun.max")
                    .font(.subheadline.weight(.medium))
            }
            .toggleStyle(.switch)
            .tint(Self.green)
        }
        .padding(16)
    }

    private func score(_ value: String, caption: String) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(value).font(.title.bold().monospacedDigit())
            Text(caption).font(.caption).foregroundStyle(.secondary)
        }
    }
}
