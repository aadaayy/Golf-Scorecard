#if DEBUG
import SwiftUI

/// The round's Lock Screen card drawn inside the app, on a dark backdrop with
/// the time above it, roughly as it looks on a locked phone. The automatic
/// checks screenshot this in case the simulator's own Lock Screen can't be
/// reached. Shown only when the app is launched with -lockScreenPreview; add
/// -alwaysOn for a rough idea of the dimmed Always-On display.
struct LockScreenCardPreview: View {
    private let alwaysOn = ProcessInfo.processInfo.arguments.contains("-alwaysOn")
    private let state = RoundActivityAttributes.ContentState(
        hole: 9, par: 4, strokes: 10, total: 62, toPar: 26, thru: 9
    )

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [alwaysOn ? .black : Color(red: 0.05, green: 0.18, blue: 0.10), .black], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(spacing: 4) {
                Text(Date.now, format: .dateTime.weekday(.wide).month().day())
                    .font(.title3.weight(.semibold))
                Text(Date.now, format: .dateTime.hour().minute())
                    .font(.system(size: 88, weight: .bold, design: .rounded))
                Spacer().frame(height: 28)
                RoundActivityView(courseName: "Pompano Beach Pines Course", state: state)
                    .environment(\.isLuminanceReduced, alwaysOn)
                    .background(Book.paper, in: RoundedRectangle(cornerRadius: 24))
                    .brightness(alwaysOn ? -0.45 : 0)
                    .padding(.horizontal, 12)
                    .accessibilityIdentifier("lock-screen-card")
            }
            .foregroundStyle(.white.opacity(alwaysOn ? 0.55 : 1))
            .padding(.top, 60)
        }
        .environment(\.colorScheme, .dark)
    }
}
#endif
