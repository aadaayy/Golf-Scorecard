import SwiftUI

/// The round's Lock Screen card, printed like a yardage book page: the hole
/// you're on and your score. Tapping it opens the round at this hole.
/// It also shows on the Always-On display, where iOS dims it; there the
/// softer pencil text turns to ink so it stays readable.
struct RoundActivityView: View {
    let courseName: String
    let state: RoundActivityAttributes.ContentState
    @Environment(\.isLuminanceReduced) private var dimmed

    /// Second lines: pencil on the lit card, ink when dimmed.
    private var note: Color { dimmed ? Book.ink : Book.pencil }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "flag.fill").foregroundStyle(Book.red)
                Text(courseName).lineLimit(1)
                Spacer(minLength: 8)
                Text(state.thru == 0 ? "Not started" : "Thru \(state.thru)")
                    .foregroundStyle(note)
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
        }
        .padding(16)
        .foregroundStyle(Book.ink)
        .fontDesign(.monospaced)
    }

    private func score(_ value: String, caption: String) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(value).font(Book.mono(28, weight: .bold))
            Text(caption).font(Book.mono(11)).foregroundStyle(note)
        }
    }
}
