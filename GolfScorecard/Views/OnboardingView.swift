import SwiftUI

/// Three short pages the first time the app opens: hello, who's playing, and
/// how the open Duo (or a sideways phone) should start. Skip works on every page.
struct OnboardingView: View {
    @AppStorage(SettingsKey.onboarded) private var onboarded = false
    @AppStorage(SettingsKey.playerName) private var playerName = ""
    @AppStorage(SettingsKey.handicap) private var handicap = ""
    @AppStorage(OpenLayout.storageKey) private var openLayout = OpenLayout.nine
    @State private var page = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                if page < 2 {
                    Button("Skip") { onboarded = true }
                        .accessibilityIdentifier("onboarding-skip")
                }
            }
            .frame(height: 44)
            .padding(.horizontal)

            // Scrolls only when a sideways phone is too short for the page.
            GeometryReader { geometry in
                ScrollView {
                    Group {
                        switch page {
                        case 0: welcome
                        case 1: aboutYou
                        default: openView
                        }
                    }
                    .frame(maxWidth: 520)
                    .padding(.horizontal, 24)
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
            }

            pageDots.padding(.bottom, 8)

            Button {
                if page < 2 {
                    withAnimation { page += 1 }
                } else {
                    onboarded = true
                }
            } label: {
                Text(page == 0 ? "Get Started" : (page == 1 ? "Next" : "Start Playing"))
                    .font(.headline)
                    .frame(maxWidth: 400)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .disabled(page == 1 && !handicapIsValid)
            .padding([.horizontal, .bottom], 24)
            .accessibilityIdentifier(page == 2 ? "onboarding-done" : "onboarding-next")
        }
        .frame(maxWidth: .infinity)
        .paperBackground()
    }

    private var welcome: some View {
        VStack(spacing: 20) {
            AppMark(size: 120)
            Text("Yardage Book").font(Book.title(36, relativeTo: .largeTitle))
            Text("Your yardage book and score card in one. Pick a course, see every hole, tap in your scores, and keep the card when you're done.")
                .font(.title3)
                .multilineTextAlignment(.center)
                .foregroundStyle(Book.pencil)
        }
    }

    private var aboutYou: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Who's playing?").font(Book.title(32, relativeTo: .largeTitle))
            VStack(alignment: .leading, spacing: 6) {
                Text("Your name").font(.headline)
                TextField("Name", text: $playerName)
                    .textContentType(.givenName)
                    .textInputAutocapitalization(.words)
                    .padding(12)
                    .bookBox(cornerRadius: 10)
                    .accessibilityIdentifier("onboarding-name")
                Text("Goes on the card as the first player.").font(.footnote).foregroundStyle(Book.pencil)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Handicap (optional)").font(.headline)
                TextField("For example 14.2", text: $handicap)
                    .keyboardType(.numbersAndPunctuation)
                    .padding(12)
                    .bookBox(cornerRadius: 10)
                    .accessibilityIdentifier("onboarding-handicap")
                Text(handicapIsValid ? "Only used to show your net score when you finish a round." : "Use a number like 14.2, or +1.5 for a plus handicap.")
                    .font(.footnote)
                    .foregroundStyle(handicapIsValid ? Book.pencil : Book.red)
            }
        }
    }

    private var openView: some View {
        VStack(spacing: 20) {
            Text("When the phone is open").font(Book.title(32, relativeTo: .largeTitle)).multilineTextAlignment(.center)
            Text("Open the Duo or turn any iPhone sideways during a round and you get two halves. Pick which you see first. You can switch any time.")
                .multilineTextAlignment(.center)
                .foregroundStyle(Book.pencil)
            HStack(spacing: 12) {
                layoutChoice(.hole, title: "Hole", detail: "Big score for the hole you're on, and its map", symbol: "flag.fill")
                layoutChoice(.nine, title: "Nine", detail: "The whole card, and all nine holes", symbol: "square.grid.3x3.fill")
            }
        }
    }

    private func layoutChoice(_ layout: OpenLayout, title: String, detail: String, symbol: String) -> some View {
        let picked = openLayout == layout
        return Button {
            openLayout = layout
        } label: {
            VStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 34)).foregroundStyle(picked ? Book.red : Book.ink)
                Text(title).font(Book.title(22, relativeTo: .title3))
                Text(detail).font(.footnote).multilineTextAlignment(.center).foregroundStyle(Book.pencil)
            }
            .frame(maxWidth: .infinity, minHeight: 150)
            .padding(12)
            .background(picked ? Book.markedRow : Book.page, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(picked ? Book.red : Book.ink.opacity(0.4), lineWidth: picked ? 2 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(picked ? .isSelected : [])
        .accessibilityIdentifier("onboarding-layout-\(layout.rawValue)")
    }

    private var pageDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(index == page ? Book.red : Book.ink.opacity(0.25))
                    .frame(width: 8, height: 8)
            }
        }
        .accessibilityHidden(true)
    }

    private var handicapIsValid: Bool {
        handicap.trimmingCharacters(in: .whitespaces).isEmpty || HandicapIndex.parse(handicap) != nil
    }
}

/// The app's mark: the app icon's yardage book page, a hole drawn in ink
/// with a red flag and a yardage arc.
struct AppMark: View {
    var size: CGFloat

    var body: some View {
        Image("BookMark")
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.22))
            .overlay(RoundedRectangle(cornerRadius: size * 0.22).stroke(Book.ink.opacity(0.6), lineWidth: 1))
            .accessibilityHidden(true)
    }
}
