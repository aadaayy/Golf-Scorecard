import AuthenticationServices
import CryptoKit
import SwiftUI
import SwiftData

// MARK: - Signing in

/// Continue with Google, and Sign in with Apple once it's turned on. No
/// email, password or codes: group rounds only take those two.
struct GroupSignInButtons: View {
    /// Called once signed in.
    var onSignedIn: () -> Void = {}

    @Environment(GroupSession.self) private var group
    @State private var working = false
    @State private var problem: String?
    @State private var appleNonce = ""

    var body: some View {
        VStack(spacing: 10) {
            Button {
                Task { await signIn { try await group.signInWithGoogle() } }
            } label: {
                HStack(spacing: 10) {
                    Text("G")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(Book.red)
                        .frame(width: 26, height: 26)
                        .background(Book.page, in: Circle())
                    Text("Continue with Google")
                        .font(Book.title(17, relativeTo: .headline))
                }
                .foregroundStyle(Book.paper)
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(Book.ink, in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .disabled(working)
            .accessibilityIdentifier("sign-in-google")

            if group.appleSignIn {
                SignInWithAppleButton(.continue) { request in
                    appleNonce = Self.randomNonce()
                    request.requestedScopes = [.fullName]
                    request.nonce = Self.sha256(appleNonce)
                } onCompletion: { result in
                    Task { await finishApple(result) }
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 46)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .disabled(working)
                .accessibilityIdentifier("sign-in-apple")
            }

            if working {
                ProgressView().accessibilityIdentifier("sign-in-working")
            }
            if let problem {
                Text(problem)
                    .font(.footnote)
                    .foregroundStyle(Book.red)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("sign-in-problem")
            }
        }
    }

    private func signIn(_ action: () async throws -> Void) async {
        working = true
        problem = nil
        defer { working = false }
        do {
            try await action()
            onSignedIn()
        } catch GroupError.cancelled {
            // They closed the sign-in page; nothing to say.
        } catch {
            problem = error.localizedDescription
        }
    }

    private func finishApple(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let token = String(data: tokenData, encoding: .utf8) else {
                problem = "Apple didn't send a sign-in. Try again."
                return
            }
            let name = credential.fullName.map { PersonNameComponentsFormatter().string(from: $0) }
            await signIn { try await group.signInWithApple(idToken: token, nonce: appleNonce, fullName: name) }
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code != .canceled {
                problem = error.localizedDescription
            }
        }
    }

    private static func randomNonce() -> String {
        let letters = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var generator = SystemRandomNumberGenerator()
        return String((0..<32).map { _ in letters.randomElement(using: &generator)! })
    }

    private static func sha256(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// A sheet that asks to sign in before a group round, and closes once done.
struct GroupSignInSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(Book.red)
                Text("Play with Friends")
                    .font(Book.title(26, relativeTo: .title))
                Text("Sign in so your friends can join your round with a code, and everyone's scores show up on everyone's card as they're entered.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Book.pencil)
                GroupSignInButtons { dismiss() }
                    .frame(maxWidth: 360)
                Text("Rounds on your own never need an account.")
                    .font(.footnote)
                    .foregroundStyle(Book.pencil)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .paperBackground()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("sign-in-cancel")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .accessibilityIdentifier("group-sign-in")
    }
}

/// Shown instead of signing in while GroupScoring.plist still has its placeholders.
struct GroupNotSetUpView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 34))
                .foregroundStyle(Book.pencil)
            Text("Group rounds aren't set up yet")
                .font(Book.title(20, relativeTo: .headline))
                .multilineTextAlignment(.center)
            Text("This copy of the app isn't connected to its group-round database. The steps are under Group rounds setup in the README.")
                .font(.subheadline)
                .foregroundStyle(Book.pencil)
                .multilineTextAlignment(.center)
        }
        .padding()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("group-not-set-up")
    }
}

// MARK: - Joining

/// Join a Group Round: sign in if needed, type the code, and the round opens
/// with everyone's scores so far. Its course downloads first if needed.
struct JoinRoundView: View {
    var startCode: String?
    /// Called with the round once joined, after which the sheet closes.
    var onJoined: (Round) -> Void

    @Environment(GroupSession.self) private var group
    @Environment(CourseLibrary.self) private var library
    @Environment(CourseCatalog.self) private var catalog
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.playerName) private var playerName = ""
    @AppStorage(SettingsKey.handicap) private var handicap = ""
    @State private var code = ""
    @State private var joining = false
    @State private var problem: String?
    @FocusState private var codeFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                if !group.isSetUp {
                    Section { GroupNotSetUpView().frame(maxWidth: .infinity) }
                        .listRowBackground(Book.page)
                } else if group.user == nil {
                    Section {
                        GroupSignInButtons().padding(.vertical, 6)
                    } header: {
                        Text("Sign in first")
                    } footer: {
                        Text("Your friends see the name you play under, nothing else.")
                    }
                    .listRowBackground(Book.page)
                } else {
                    codeSection
                }
            }
            .bookList()
            .navigationTitle("Join a Group Round")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("join-cancel")
                }
            }
        }
        .onAppear {
            if let startCode { code = JoinCode.spaced(startCode) }
        }
        .accessibilityIdentifier("join-round")
    }

    private var cleanCode: String { JoinCode.clean(code) }

    private var codeSection: some View {
        Group {
            Section {
                TextField("ABC 234", text: $code)
                    .font(.system(size: 34, weight: .bold, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .focused($codeFocused)
                    .onChange(of: code) { _, typed in
                        // Show the code the way it's printed: capitals, no stray letters.
                        let upper = typed.uppercased()
                        if upper != typed { code = upper }
                    }
                    .submitLabel(.join)
                    .onSubmit { Task { await join() } }
                    .accessibilityIdentifier("join-code")
            } header: {
                Text("Code from the player who started")
            } footer: {
                if let problem {
                    Text(problem).foregroundStyle(Book.red).accessibilityIdentifier("join-problem")
                } else {
                    Text("You'll play as \(nameToPlayAs). Everyone keeps their own score, and you'll see theirs as they enter them.")
                }
            }
            .listRowBackground(Book.page)

            Section {
                Button {
                    Task { await join() }
                } label: {
                    HStack {
                        if joining { ProgressView().tint(Book.paper) }
                        Label(joining ? "Joining…" : "Join Round", systemImage: "person.2.fill")
                    }
                    .font(Book.title(19, relativeTo: .headline))
                    .foregroundStyle(Book.paper)
                    .frame(maxWidth: .infinity)
                }
                .disabled(!JoinCode.isValid(cleanCode) || joining)
                .listRowBackground(JoinCode.isValid(cleanCode) ? Book.ink : Book.ink.opacity(0.4))
                .accessibilityIdentifier("join-submit")
            }
        }
    }

    private var nameToPlayAs: String {
        let trimmed = playerName.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? (group.user?.name ?? "Player") : trimmed
    }

    private func join() async {
        guard JoinCode.isValid(cleanCode), !joining else { return }
        joining = true
        problem = nil
        defer { joining = false }
        do {
            let round = try await group.joinRound(code: cleanCode, playerName: nameToPlayAs,
                                                  handicap: HandicapIndex.parse(handicap),
                                                  library: library, catalog: catalog, in: modelContext)
            onJoined(round)
            dismiss()
        } catch {
            problem = error.localizedDescription
        }
    }
}

// MARK: - During a group round

/// The strip above a group round's card: whether it's live, the code, how
/// many have joined, and Invite to send the code.
struct GroupRoundBar: View {
    let round: Round
    let sync: GroupRoundSync?
    @Environment(GroupSession.self) private var group
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    var body: some View {
        HStack(spacing: 12) {
            status
            Spacer(minLength: 4)
            if let code = round.groupCode {
                VStack(alignment: .trailing, spacing: 0) {
                    Text("CODE").font(.caption2.weight(.bold)).foregroundStyle(Book.pencil)
                    Text(JoinCode.spaced(code))
                        .font(.system(size: verticalSizeClass == .compact ? 17 : 20, weight: .bold, design: .monospaced))
                        .accessibilityLabel("Code \(code.map(String.init).joined(separator: " "))")
                        .accessibilityIdentifier("group-code")
                }
                ShareLink(item: JoinCode.link(for: code),
                          subject: Text("Join my round"),
                          message: Text("Join my round at \(round.courseName) in Yardage Book. Open the app, tap Join a Group Round on Play and type \(JoinCode.spaced(code)), or tap this link:")) {
                    Label("Invite", systemImage: "square.and.arrow.up")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Book.page, in: Capsule())
                        .overlay(Capsule().stroke(Book.ink.opacity(0.6), lineWidth: 1))
                }
                .accessibilityIdentifier("group-invite")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, verticalSizeClass == .compact ? 4 : 8)
        .background(Book.paper)
        .overlay(alignment: .bottom) { Rectangle().fill(Book.rule).frame(height: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("group-bar")
    }

    private var statusText: (String, Color) {
        guard group.user != nil else { return ("Sign in to see friends", Book.red) }
        switch sync?.status ?? .offline {
        case .connecting: return ("Connecting", Book.pencil)
        case .live: return ("Live", Book.leaf)
        case .offline: return ("Offline · scores send later", Book.red)
        }
    }

    private var status: some View {
        let (text, color) = statusText
        let others = max(round.players.count - 1, 0)
        return VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(text).font(.subheadline.weight(.semibold)).foregroundStyle(color)
                    .accessibilityIdentifier("group-status")
            }
            Text(others == 0 ? "Waiting for friends" : "\(round.players.count) of \(GroupCard.maxPlayers) playing")
                .font(.caption)
                .foregroundStyle(Book.pencil)
                .accessibilityIdentifier("group-count")
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}

/// Below the card when a friend's row is picked: their score is theirs to enter.
struct FriendScoreBar: View {
    let playerName: String
    let hole: Int
    let strokes: Int

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(playerName).font(Book.title(19, relativeTo: .headline))
                Text("Enters their own score").font(.subheadline).foregroundStyle(Book.pencil)
            }
            Spacer()
            Text(strokes > 0 ? "\(strokes)" : "–")
                .font(.title.weight(.bold))
                .frame(minWidth: 40)
                .accessibilityIdentifier("friend-score-value")
            Image(systemName: "dot.radiowaves.left.and.right").foregroundStyle(Book.leaf)
        }
        .padding(12)
        .bookBox()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("friend-score-bar")
    }
}

// MARK: - Account in Profile

/// Profile's account rows: sign in for group rounds, or who's signed in with
/// Sign Out and Delete Account.
struct GroupAccountSection: View {
    @Environment(GroupSession.self) private var group
    @State private var confirmingDelete = false
    @State private var problem: String?

    var body: some View {
        Section {
            if !group.isSetUp {
                Text("Group rounds aren't set up in this copy of the app yet.")
                    .foregroundStyle(Book.pencil)
                    .accessibilityIdentifier("account-not-set-up")
            } else if let user = group.user {
                LabeledContent {
                    Text(user.name).accessibilityIdentifier("account-name")
                } label: {
                    Label("Signed in", systemImage: "person.crop.circle.badge.checkmark")
                }
                Button("Sign Out") {
                    Task { await group.signOut() }
                }
                .accessibilityIdentifier("account-sign-out")
                Button("Delete Account", role: .destructive) {
                    confirmingDelete = true
                }
                .foregroundStyle(Book.red)
                .accessibilityIdentifier("account-delete")
            } else {
                GroupSignInButtons().padding(.vertical, 6)
            }
        } header: {
            Text("Account for Group Rounds")
        } footer: {
            if let problem {
                Text(problem).foregroundStyle(Book.red)
            } else {
                Text("Only needed to play with friends. Rounds on your own stay on this phone and never need an account.")
            }
        }
        .confirmationDialog("Delete your account?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete Account", role: .destructive) {
                Task {
                    do {
                        try await group.deleteAccount()
                        problem = nil
                    } catch {
                        problem = error.localizedDescription
                    }
                }
            }
            .accessibilityIdentifier("confirm-delete-account")
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your account and the scores you sent to group rounds are deleted. Rounds saved on this phone stay.")
        }
    }
}

extension EnvironmentValues {
    /// Opens Join a Group Round, with a code from a link when there is one. Set by RootView.
    @Entry var joinGroupRound: (String?) -> Void = { _ in }
}
