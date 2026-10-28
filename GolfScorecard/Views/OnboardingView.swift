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
        .background(Color(.systemBackground))
    }

    private var welcome: some View {
        VStack(spacing: 20) {
            AppMark(size: 120)
            Text("Scorecard").font(.largeTitle.bold())
            Text("Your paper scorecard, on your phone. Pick a course, tap in your scores, and keep the card when you're done.")
                .font(.title3)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
    }

    private var aboutYou: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Who's playing?").font(.largeTitle.bold())
            VStack(alignment: .leading, spacing: 6) {
                Text("Your name").font(.headline)
                TextField("Name", text: $playerName)
                    .textContentType(.givenName)
                    .textInputAutocapitalization(.words)
                    .padding(12)
                    .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityIdentifier("onboarding-name")
                Text("Goes on the card as the first player.").font(.footnote).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Handicap (optional)").font(.headline)
                TextField("For example 14.2", text: $handicap)
                    .keyboardType(.numbersAndPunctuation)
                    .padding(12)
                    .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityIdentifier("onboarding-handicap")
                Text(handicapIsValid ? "Only used to show your net score when you finish a round." : "Use a number like 14.2, or +1.5 for a plus handicap.")
                    .font(.footnote)
                    .foregroundStyle(handicapIsValid ? Color.secondary : Color.red)
            }
        }
    }

    private var openView: some View {
        VStack(spacing: 20) {
            Text("When the phone is open").font(.largeTitle.bold()).multilineTextAlignment(.center)
            Text("Open the Duo or turn any iPhone sideways during a round and you get two halves. Pick which you see first. You can switch any time.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
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
                Image(systemName: symbol).font(.system(size: 34))
                Text(title).font(.title3.bold())
                Text(detail).font(.footnote).multilineTextAlignment(.center).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 150)
            .padding(12)
            .background(picked ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(picked ? Color.accentColor : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(picked ? .isSelected : [])
        .accessibilityIdentifier("onboarding-layout-\(layout.rawValue)")
    }

    private var pageDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(index == page ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 8, height: 8)
            }
        }
        .accessibilityHidden(true)
    }

    private var handicapIsValid: Bool {
        handicap.trimmingCharacters(in: .whitespaces).isEmpty || HandicapIndex.parse(handicap) != nil
    }
}

/// The app's mark: a flag on a paper card, as on the app icon.
struct AppMark: View {
    var size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22)
                .fill(Color(red: 0.18, green: 0.49, blue: 0.24))
            RoundedRectangle(cornerRadius: size * 0.06)
                .fill(Color(red: 0.98, green: 0.97, blue: 0.92))
                .frame(width: size * 0.58, height: size * 0.66)
                .rotationEffect(.degrees(-6))
            Image(systemName: "flag.fill")
                .font(.system(size: size * 0.32))
                .foregroundStyle(Color(red: 0.85, green: 0.16, blue: 0.20))
                .offset(x: size * 0.03)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
