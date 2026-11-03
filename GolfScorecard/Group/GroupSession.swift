import Foundation
import Observation
import SwiftData

/// Group rounds for the whole app: who's signed in, and starting or joining
/// a round. Each round's live updates are kept by `GroupRoundSync`.
@MainActor
@Observable
final class GroupSession {
    /// Nil while GroupScoring.plist still has its placeholders.
    let service: GroupService?
    let appleSignIn: Bool
    private(set) var user: GroupUser?
    /// A reset-password link was opened: ask for the new password.
    var needsNewPassword = false
    /// A link from an email that didn't work, said once.
    var linkProblem: String?

    /// The email a reset link was last asked for. Supabase's link signs the
    /// golfer in like any other, so this is how the app knows to ask for a
    /// new password when it opens.
    private var pendingResetEmail: String? {
        get { UserDefaults.standard.string(forKey: "groupPendingResetEmail") }
        set { UserDefaults.standard.set(newValue, forKey: "groupPendingResetEmail") }
    }

    var isSetUp: Bool { service != nil }

    /// The app runs on accounts: until someone is signed in (or while a reset
    /// link waits for its new password), the account screen covers it. Only
    /// while the app isn't connected to its project does it work without one.
    var needsAccount: Bool { isSetUp && (user == nil || needsNewPassword) }

    init(service: GroupService?, appleSignIn: Bool) {
        self.service = service
        self.appleSignIn = appleSignIn
        user = service?.currentUser()
    }

    /// The real project from GroupScoring.plist, or the pretend one the checks use.
    static func make(arguments: [String] = ProcessInfo.processInfo.arguments) -> GroupSession {
        #if DEBUG
        if arguments.contains("-mockGroup") {
            return GroupSession(service: MockGroupService(signedIn: arguments.contains("-mockSignedIn")),
                                appleSignIn: arguments.contains("-mockAppleSignIn"))
        }
        if arguments.contains("-uiTesting") {
            // The checks never reach a real project, even once one is filled in.
            return GroupSession(service: nil, appleSignIn: false)
        }
        #endif
        guard let config = GroupConfig.load() else { return GroupSession(service: nil, appleSignIn: false) }
        return GroupSession(service: SupabaseGroupService(config: config), appleSignIn: config.appleSignIn)
    }

    private func requireService() throws -> GroupService {
        guard let service else { throw GroupError.notSetUp }
        return service
    }

    func signInWithGoogle() async throws {
        user = try await requireService().signInWithGoogle()
    }

    func signInWithApple(idToken: String, nonce: String, fullName: String?) async throws {
        user = try await requireService().signInWithApple(idToken: idToken, nonce: nonce, fullName: fullName)
    }

    func signInWithEmail(email: String, password: String) async throws {
        user = try await requireService().signInWithEmail(email: email, password: password)
    }

    /// Makes an account. Signed in straight away, or once the link in the
    /// email is opened on this phone (see `handle`).
    func signUpWithEmail(email: String, password: String, name: String?) async throws -> EmailSignUpResult {
        let result = try await requireService().signUpWithEmail(email: email, password: password, name: name)
        if case .signedIn(let signedIn) = result { user = signedIn }
        return result
    }

    func resendConfirmation(email: String) async throws {
        try await requireService().resendConfirmation(email: email)
    }

    func sendPasswordReset(email: String) async throws {
        try await requireService().sendPasswordReset(email: email)
        pendingResetEmail = EmailCheck.clean(email)
    }

    func updatePassword(_ password: String) async throws {
        try await requireService().updatePassword(password)
        pendingResetEmail = nil
    }

    func signOut() async {
        await service?.signOut()
        user = nil
    }

    func deleteAccount() async throws {
        try await requireService().deleteAccount()
        user = nil
    }

    /// A golfscorecard://login-callback link: the way back from Google's page,
    /// or a link in a confirm or reset email.
    func handle(_ url: URL) async {
        guard let service else { return }
        do {
            let signedIn = try await service.openLink(url)
            user = signedIn
            if let pending = pendingResetEmail, signedIn.email.map(EmailCheck.clean) == pending {
                needsNewPassword = true
            }
        } catch {
            // Google's sheet finishes on its own and its link may arrive here
            // too, already used: only say something if nobody got signed in.
            try? await Task.sleep(for: .seconds(1))
            if user == nil { linkProblem = error.localizedDescription }
        }
    }

    /// Starts a group round: saved on this phone like any round, with the
    /// golfer as the only player until friends join.
    func startRound(course: Course, tee: String, playerName: String, handicap: Double?, in context: ModelContext) async throws -> Round {
        let service = try requireService()
        guard let user else { throw GroupError.notSignedIn }
        let info = try await service.startRound(courseID: course.id, courseName: course.name, tee: tee, playerName: playerName)
        let round = Round(course: course, tee: tee, players: [playerName], playerHandicap: handicap)
        round.groupRoundID = info.id
        round.groupCode = info.code
        round.groupSeat = 0
        round.groupIsHost = info.hostID == user.id
        context.insert(round)
        return round
    }

    /// Joins a friend's round: downloads its course if the phone doesn't have
    /// it, then saves the round on this phone with everyone's scores so far.
    func joinRound(code: String, playerName: String, handicap: Double?,
                   library: CourseLibrary, catalog: CourseCatalog, in context: ModelContext) async throws -> Round {
        let service = try requireService()
        guard let user else { throw GroupError.notSignedIn }
        let info = try await service.joinRound(code: code, playerName: playerName)

        // Back to a round already on this phone.
        let id: String? = info.id
        if let existing = try? context.fetch(FetchDescriptor<Round>(predicate: #Predicate { $0.groupRoundID == id })).first {
            return existing
        }

        if library.course(id: info.courseID) == nil {
            await catalog.load()
            if let entry = catalog.index?.courses.first(where: { $0.id == info.courseID }) {
                await catalog.download(entry, into: library)
            }
        }
        guard let course = library.course(id: info.courseID) else { throw GroupError.courseMissing(info.courseName) }

        let state = try await service.fetch(roundID: info.id)
        guard let mine = state.players.first(where: { $0.userID == user.id }) else { throw GroupError.noSuchRound }
        let tee = course.tees.contains(info.tee) ? info.tee : course.tees.first ?? info.tee
        let round = Round(course: course, tee: tee, players: [playerName], playerHandicap: handicap)
        round.groupRoundID = info.id
        round.groupCode = info.code
        round.groupSeat = mine.seat
        round.groupIsHost = info.hostID == user.id
        var card = GroupCard(names: [], grid: StrokeGrid(playerCount: 0), mySeat: mine.seat)
        card.apply(players: state.players)
        card.apply(scores: state.scores, players: state.players)
        card.fillMine(from: state.scores, myUserID: user.id)
        var names = card.names
        names[mine.seat] = playerName
        round.players = names
        round.strokes = card.grid.values
        context.insert(round)
        return round
    }
}
