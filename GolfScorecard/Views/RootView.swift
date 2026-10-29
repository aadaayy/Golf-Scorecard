import SwiftUI
import SwiftData

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
    /// The hole to open the round on, when the Lock Screen card opened it.
    @State private var openRoundHole: Int?
    @Environment(\.modelContext) private var modelContext
    /// Bumped by Erase Everything, so each tab starts again from its top screen.
    @State private var resetCount = 0

    var body: some View {
        TabView(selection: $tab) {
            Tab("Play", systemImage: "flag", value: AppTab.play) {
                HomeView()
            }
            Tab("Past Rounds", systemImage: "book.closed", value: AppTab.pastRounds) {
                NavigationStack {
                    PastRoundsView()
                }
            }
            Tab("Profile", systemImage: "person", value: AppTab.profile) {
                NavigationStack {
                    ProfileView(onErase: {
                        tab = .play
                        resetCount += 1
                    }, onShowPastRounds: {
                        tab = .pastRounds
                    })
                }
            }
        }
        .id(resetCount)
        .environment(\.openRound, { round in
            openRoundHole = nil
            openRound = round
        })
        .fullScreenCover(item: $openRound) { round in
            NavigationStack {
                RoundView(round: round, showsCloseButton: true, startHole: openRoundHole)
            }
        }
        .onOpenURL(perform: openFromLockScreen)
        .task { endLeftoverLockScreenCards() }
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

extension RootView {
    /// The round's Lock Screen card was tapped: open that round at its hole.
    /// The link looks like golfscorecard://round?start=…&hole=7.
    private func openFromLockScreen(_ url: URL) {
        guard url.scheme == "golfscorecard", url.host == "round" else { return }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let start = items.first { $0.name == "start" }?.value.flatMap(Double.init)
        let hole = items.first { $0.name == "hole" }?.value.flatMap(Int.init)
        let unfinished = (try? modelContext.fetch(FetchDescriptor<Round>(
            predicate: #Predicate<Round> { $0.finishedAt == nil },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        ))) ?? []
        let round = unfinished.first { start != nil && abs($0.date.timeIntervalSinceReferenceDate - start!) < 0.01 } ?? unfinished.first
        guard let round else { return }
        if openRound?.persistentModelID == round.persistentModelID {
            if let hole { NotificationCenter.default.post(name: .showLiveRoundHole, object: hole) }
        } else {
            openRoundHole = hole
            openRound = round
        }
    }

    /// A card can outlive its round, for example when the app was closed and
    /// the round was then deleted or finished. Only rounds being played keep one.
    private func endLeftoverLockScreenCards() {
        let unfinished = (try? modelContext.fetch(FetchDescriptor<Round>(predicate: #Predicate<Round> { $0.finishedAt == nil }))) ?? []
        LiveRound.endCards(exceptRoundsStartedAt: Set(unfinished.map { $0.date.timeIntervalSinceReferenceDate }))
    }
}

enum AppTab: Hashable {
    case play, pastRounds, profile
}

extension EnvironmentValues {
    /// Opens a round over the whole screen. Set by RootView.
    @Entry var openRound: (Round) -> Void = { _ in }
}
