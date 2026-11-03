import Foundation

/// The signed-in golfer, as group rounds know them.
struct GroupUser: Equatable {
    var id: String
    var name: String
    /// The account's email, when it has one.
    var email: String? = nil
}

/// What happened after Create Account with an email.
enum EmailSignUpResult: Equatable {
    /// Signed in straight away (the project doesn't ask to confirm emails).
    case signedIn(GroupUser)
    /// A link went to the email; opening it on this phone finishes signing in.
    case checkEmail
}

/// A group round as the database has it.
struct GroupRoundInfo: Equatable {
    var id: String
    var code: String
    var courseID: String
    var courseName: String
    var tee: String
    var hostID: String?
    var isFinished: Bool
}

/// Something that happened in a group round while it's open.
enum GroupEvent: Equatable {
    case player(GroupPlayer)
    case score(GroupScore)
}

/// Accounts and group rounds. `SupabaseGroupService` talks to the real
/// database; `MockGroupService` stands in for it in the automatic checks.
@MainActor
protocol GroupService: AnyObject {
    /// Whoever is signed in on this phone, if anyone. Doesn't need a signal.
    func currentUser() -> GroupUser?
    func signInWithGoogle() async throws -> GroupUser
    /// The token and nonce from Sign in with Apple. Apple only gives the name
    /// the first time, so it's saved when it comes.
    func signInWithApple(idToken: String, nonce: String, fullName: String?) async throws -> GroupUser
    /// Email and password: signing in, making an account, and the emails
    /// that confirm an account or set a new password.
    func signInWithEmail(email: String, password: String) async throws -> GroupUser
    func signUpWithEmail(email: String, password: String, name: String?) async throws -> EmailSignUpResult
    func resendConfirmation(email: String) async throws
    func sendPasswordReset(email: String) async throws
    /// A link from one of those emails (or from Google's page) opened the app.
    func openLink(_ url: URL) async throws -> GroupUser
    /// Sets a new password for whoever is signed in.
    func updatePassword(_ password: String) async throws
    func signOut() async
    /// Deletes the account and everything that's only theirs, then signs out.
    func deleteAccount() async throws

    /// Starts a round with the signed-in golfer in seat 0.
    func startRound(courseID: String, courseName: String, tee: String, playerName: String) async throws -> GroupRoundInfo
    /// Takes a free seat in the round with this code.
    func joinRound(code: String, playerName: String) async throws -> GroupRoundInfo
    /// Everyone in the round and every score so far.
    func fetch(roundID: String) async throws -> (players: [GroupPlayer], scores: [GroupScore])
    /// The signed-in golfer's strokes, by hole.
    func send(strokes: [Int: Int], roundID: String) async throws
    /// The host finished: the code stops working.
    func finish(roundID: String) async throws
    /// New players and scores as they happen. Ends when the connection drops.
    func events(roundID: String) -> AsyncStream<GroupEvent>
}

enum GroupError: LocalizedError, Equatable {
    case notSetUp
    case notSignedIn
    case cancelled
    case noSuchRound
    case roundFull
    case tooManyToday
    case courseMissing(String)
    case wrongPassword
    case emailNotConfirmed
    case accountExists
    case weakPassword
    case badEmail
    case tooManyEmails
    case emailNotSent
    case emailTurnedOff
    case linkFailed
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .notSetUp: "Group rounds aren't set up in this copy of the app yet."
        case .notSignedIn: "Sign in to play group rounds."
        case .cancelled: "Sign in was cancelled."
        case .noSuchRound: "No round with that code. Codes work for a day, until the round is finished."
        case .roundFull: "That round already has four players."
        case .tooManyToday: "That's a lot of group rounds for one day. Try again tomorrow."
        case .courseMissing(let name): "\(name) couldn't be downloaded. Find it in Find Courses on Play, then join again."
        case .wrongPassword: "That email and password don't match. Check them, or tap Forgot Password."
        case .emailNotConfirmed: "Confirm your email first: open the link we sent you on this phone."
        case .accountExists: "There's already an account with that email. Sign in instead."
        case .weakPassword: "Pick a longer password, at least \(EmailCheck.minimumPasswordLength) characters."
        case .badEmail: "That email address doesn't look right."
        case .tooManyEmails: "Too many emails sent just now. Wait a few minutes and try again."
        case .emailNotSent: "The email couldn't be sent to that address. Try again later, or use Google."
        case .emailTurnedOff: "Email sign-in is turned off right now. Use Google instead."
        case .linkFailed: "That link didn't work. It may have expired or been opened on another phone. Send a new one and open it on this phone."
        case .failed(let message): message
        }
    }
}

