import SwiftUI

/// The app's three places, one tab each: Play, Past Rounds and Profile.
///
/// On the iPhone Duo the system puts the tabs in the strip at the side of the
/// screen, under Back, so the rest of the screen is all content. Regular
/// iPhones show them along the bottom. The same tabs show closed and open, so
/// nothing jumps when the Duo is unfolded. A round opens over the whole
/// screen, tabs included, since it has its own Card and Map tabs.
struct RootView: View {
    @AppStorage(SettingsKey.onboarded) private var onboarded = false
    @State private var tab = AppTab.play
    /// The round being played or looked at. It covers the whole screen, tabs
    /// included, since a round has its own Card and Map tabs.
    @State private var openRound: Round?
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
        .environment(\.openRound, { round in openRound = round })
        .fullScreenCover(item: $openRound) { round in
            NavigationStack {
                RoundView(round: round, showsCloseButton: true)
            }
        }
        .overlay {
            // The welcome pages, the first time. Hosted on an empty overlay so
            // they don't share a presenter with the round.
            Color.clear
                .allowsHitTesting(false)
                .fullScreenCover(isPresented: Binding(get: { !onboarded }, set: { onboarded = !$0 })) {
                    OnboardingView()
                }
        }
    }
}

enum AppTab: Hashable {
    case play, pastRounds, profile
}

extension EnvironmentValues {
    /// Opens a round over the whole screen. Set by RootView.
    @Entry var openRound: (Round) -> Void = { _ in }
}
