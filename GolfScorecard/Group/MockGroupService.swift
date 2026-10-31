#if DEBUG
import Foundation

/// A pretend group-round server on the phone, for the automatic checks, which
/// have no Supabase project and no Google account. Launched with -mockGroup
/// (and -mockSignedIn to start signed in).
///
/// Friends play along on their own: in a round you start, Sam and Jordan join
/// a moment later, and each scores a hole shortly after you do (Sam one more
/// than you, Jordan the same). The code GREEN4 joins Sam's round already on
/// hole 4; PACKED is a round with no seats left; any other code isn't found.
@MainActor
final class MockGroupService: GroupService {
    static let me = GroupUser(id: "mock-me", name: "Alex Rivera")
    static let startCode = "PNS234"
    static let joinCode = "GREEN4"
    static let fullCode = "PACKED"

    private var user: GroupUser?
    private var rounds: [String: MockRound] = [:]
    private var listeners: [String: [AsyncStream<GroupEvent>.Continuation]] = [:]
    /// How long friends take, shortened in the checks' preview screens.
    private let pause: Duration

    private struct MockRound {
        var info: GroupRoundInfo
        var players: [GroupPlayer]
        var scores: [GroupScore]
    }

    init(signedIn: Bool, pause: Duration = .milliseconds(1200)) {
        user = signedIn ? Self.me : nil
        self.pause = pause
    }

    func currentUser() -> GroupUser? { user }

    func signInWithGoogle() async throws -> GroupUser {
        try await Task.sleep(for: .milliseconds(300))
        user = Self.me
        return Self.me
    }

    func signInWithApple(idToken: String, nonce: String, fullName: String?) async throws -> GroupUser {
        user = Self.me
        return Self.me
    }

    func signOut() async { user = nil }

    func deleteAccount() async throws {
        user = nil
        rounds = [:]
    }

    func startRound(courseID: String, courseName: String, tee: String, playerName: String) async throws -> GroupRoundInfo {
        guard let user else { throw GroupError.notSignedIn }
        let info = GroupRoundInfo(id: "mock-started", code: Self.startCode, courseID: courseID, courseName: courseName,
                                  tee: tee, hostID: user.id, isFinished: false)
        rounds[info.id] = MockRound(info: info, players: [GroupPlayer(userID: user.id, seat: 0, name: playerName)], scores: [])
        Task {
            try? await Task.sleep(for: pause)
            add(GroupPlayer(userID: "mock-sam", seat: 1, name: "Sam"), to: info.id)
            try? await Task.sleep(for: pause)
            add(GroupPlayer(userID: "mock-jordan", seat: 2, name: "Jordan"), to: info.id)
        }
        return info
    }

    func joinRound(code: String, playerName: String) async throws -> GroupRoundInfo {
        guard let user else { throw GroupError.notSignedIn }
        try await Task.sleep(for: .milliseconds(300))
        switch code {
        case Self.fullCode: throw GroupError.roundFull
        case Self.joinCode: break
        default: throw GroupError.noSuchRound
        }
        let info = GroupRoundInfo(id: "mock-joined", code: code, courseID: "pompano-pines", courseName: "Pompano Beach Pines",
                                  tee: "White", hostID: "mock-sam", isFinished: false)
        if rounds[info.id] == nil {
            var scores: [GroupScore] = []
            for (hole, sam, jordan) in [(1, 6, 5), (2, 4, 5), (3, 3, 4)] {
                scores.append(GroupScore(userID: "mock-sam", hole: hole, strokes: sam))
                scores.append(GroupScore(userID: "mock-jordan", hole: hole, strokes: jordan))
            }
            rounds[info.id] = MockRound(info: info, players: [
                GroupPlayer(userID: "mock-sam", seat: 0, name: "Sam"),
                GroupPlayer(userID: "mock-jordan", seat: 1, name: "Jordan"),
                GroupPlayer(userID: user.id, seat: 2, name: playerName),
            ], scores: scores)
        }
        return info
    }

    func fetch(roundID: String) async throws -> (players: [GroupPlayer], scores: [GroupScore]) {
        guard let round = rounds[roundID] else { throw GroupError.noSuchRound }
        return (round.players, round.scores)
    }

    func send(strokes: [Int: Int], roundID: String) async throws {
        guard let user, rounds[roundID] != nil else { throw GroupError.notSignedIn }
        for (hole, value) in strokes.sorted(by: { $0.key < $1.key }) {
            record(GroupScore(userID: user.id, hole: hole, strokes: value), in: roundID)
            // Friends score the same hole a moment later.
            guard value > 0 else { continue }
            Task {
                try? await Task.sleep(for: pause / 2)
                for friend in rounds[roundID]?.players ?? [] where friend.userID != user.id {
                    let strokes = friend.userID == "mock-sam" ? value + 1 : value
                    record(GroupScore(userID: friend.userID, hole: hole, strokes: strokes), in: roundID)
                }
            }
        }
    }

    func finish(roundID: String) async throws {
        rounds[roundID]?.info.isFinished = true
    }

    func events(roundID: String) -> AsyncStream<GroupEvent> {
        AsyncStream { continuation in
            listeners[roundID, default: []].append(continuation)
        }
    }

    private func add(_ player: GroupPlayer, to roundID: String) {
        guard rounds[roundID] != nil, !(rounds[roundID]!.players.contains { $0.userID == player.userID }) else { return }
        rounds[roundID]!.players.append(player)
        listeners[roundID]?.forEach { $0.yield(.player(player)) }
    }

    private func record(_ score: GroupScore, in roundID: String) {
        guard rounds[roundID] != nil else { return }
        rounds[roundID]!.scores.removeAll { $0.userID == score.userID && $0.hole == score.hole }
        rounds[roundID]!.scores.append(score)
        listeners[roundID]?.forEach { $0.yield(.score(score)) }
    }
}
#endif
