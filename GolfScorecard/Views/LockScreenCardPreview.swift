#if DEBUG
import SwiftUI

/// The round's Lock Screen card drawn inside the app, on a dark backdrop with
/// the time above it, roughly as it looks on a locked phone. The automatic
/// checks screenshot this in case the simulator's own Lock Screen can't be
/// reached. Shown only when the app is launched with -lockScreenPreview.
struct LockScreenCardPreview: View {
    private let state = RoundActivityAttributes.ContentState(
        hole: 9, par: 4, strokes: 10, total: 62, toPar: 26, thru: 9, keepScreenOn: false
    )

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [Color(red: 0.05, green: 0.18, blue: 0.10), .black], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(spacing: 4) {
                Text(Date.now, format: .dateTime.weekday(.wide).month().day())
                    .font(.title3.weight(.semibold))
                Text(Date.now, format: .dateTime.hour().minute())
                    .font(.system(size: 88, weight: .bold, design: .rounded))
                Spacer().frame(height: 28)
                RoundActivityView(courseName: "Pompano Beach Pines Course", state: state)
                    .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 24))
                    .padding(.horizontal, 12)
                    .accessibilityIdentifier("lock-screen-card")
            }
            .foregroundStyle(.white)
            .padding(.top, 60)
        }
        .environment(\.colorScheme, .dark)
    }
}
#endif
