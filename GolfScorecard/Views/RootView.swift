import SwiftUI

/// The app's three places, one tab each: Play, Past Rounds and Profile.
///
/// On the iPhone Duo the system puts the tabs in the strip at the side of the
/// screen, under Back, so the rest of the screen is all content. Regular
/// iPhones show them along the bottom. The same tabs show closed and open, so
/// nothing jumps when the Duo is unfolded. A round hides them (see RoundView),
/// since it has its own Card and Map tabs.
struct RootView: View {
    @AppStorage(SettingsKey.onboarded) private var onboarded = false
    @State private var tab = AppTab.play
    /// Bumped by Erase Everything, so each tab starts again from its top screen.
    @State private var resetCount = 0

    var body: some View {
        TabView(selection: $tab) {
            Tab("Play", systemImage: "figure.golf", value: AppTab.play) {
                HomeView()
            }
            Tab("Past Rounds", systemImage: "clock.arrow.circlepath", value: AppTab.pastRounds) {
                NavigationStack {
                    PastRoundsView()
                        .navigationDestination(for: Round.self) { RoundView(round: $0) }
                }
            }
            Tab("Profile", systemImage: "person.crop.circle", value: AppTab.profile) {
                NavigationStack {
                    ProfileView {
                        tab = .play
                        resetCount += 1
                    }
                }
            }
        }
        .id(resetCount)
        .fullScreenCover(isPresented: Binding(get: { !onboarded }, set: { onboarded = !$0 })) {
            OnboardingView()
        }
    }
}

enum AppTab: Hashable {
    case play, pastRounds, profile
}
