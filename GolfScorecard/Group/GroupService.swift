import Foundation

/// The signed-in golfer, as group rounds know them.
struct GroupUser: Equatable {
    var id: String
    var name: String
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
        case .failed(let message): message
        }
    }
}
