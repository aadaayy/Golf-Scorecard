import AppIntents
import SwiftUI

/// The round's Lock Screen card, printed like a yardage book page: the hole
/// you're on, your score, and a button to keep the screen on. Tapping
/// anywhere else opens the round at this hole.
struct RoundActivityView: View {
    let courseName: String
    let state: RoundActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "flag.fill").foregroundStyle(Book.red)
                Text(courseName).lineLimit(1)
                Spacer(minLength: 8)
                Text(state.thru == 0 ? "Not started" : "Thru \(state.thru)")
                    .foregroundStyle(Book.pencil)
            }
            .font(Book.mono(14, weight: .semibold))

            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("HOLE \(state.hole)")
                        .font(Book.title(26, relativeTo: .title2))
                        .accessibilityLabel("Hole \(state.hole)")
                    if let par = state.par {
                        Text("PAR \(par)")
                            .font(Book.title(16, relativeTo: .subheadline))
                            .foregroundStyle(Book.red)
                            .accessibilityLabel("Par \(par)")
                    }
                }
                Spacer()
                score(state.strokes > 0 ? "\(state.strokes)" : "–", caption: "This hole")
                score("\(state.total)", caption: state.thru == 0 ? "Total" : "Total \(state.toParText)")
                    .padding(.leading, 18)
            }

            KeepScreenOnButton(isOn: state.keepScreenOn)
        }
        .padding(16)
        .foregroundStyle(Book.ink)
        .fontDesign(.monospaced)
    }

    private func score(_ value: String, caption: String) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(value).font(Book.mono(28, weight: .bold))
            Text(caption).font(Book.mono(11)).foregroundStyle(Book.pencil)
        }
    }
}

/// Keep screen on, with an On or Off pill. A button rather than a switch,
/// since Lock Screen cards draw buttons everywhere a switch may not show.
/// On the paper card it's ink on paper; in the Dynamic Island, light on dark.
struct KeepScreenOnButton: View {
    let isOn: Bool
    var onDark = false

    var body: some View {
        Button(intent: KeepScreenOnIntent(on: !isOn)) {
            HStack {
                Label("Keep screen on", systemImage: isOn ? "sun.max.fill" : "sun.max")
                    .font(Book.mono(14, weight: .medium))
                Spacer()
                Text(isOn ? "On" : "Off")
                    .font(Book.mono(14, weight: .bold))
                    .foregroundStyle(pillText)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 5)
                    .background(pill, in: Capsule())
                    .overlay(Capsule().stroke(onDark ? Color.clear : Book.ink, lineWidth: 1))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Keep screen on")
        .accessibilityValue(isOn ? "On" : "Off")
    }

    private var pill: Color {
        if onDark { return isOn ? Book.paper : Color.white.opacity(0.22) }
        return isOn ? Book.ink : Book.shade
    }

    private var pillText: Color {
        if onDark { return isOn ? Book.ink : .white }
        return isOn ? Book.paper : Book.ink
    }
}
