import AuthenticationServices
import Foundation
import Supabase

/// Group rounds on Supabase: accounts from Supabase Auth (Google, and Apple
/// once it's turned on), tables and functions from supabase/migrations, and
/// live updates from Supabase Realtime.
@MainActor
final class SupabaseGroupService: GroupService {
    /// Where Google sends the golfer back after signing in. Add it to the
    /// project's redirect URLs (README).
    static let callbackURL = URL(string: "golfscorecard://login-callback")!

    private let client: SupabaseClient

    init(config: GroupConfig) {
        client = SupabaseClient(
            supabaseURL: config.url,
            supabaseKey: config.key,
            options: SupabaseClientOptions(
                auth: .init(
                    storage: KeychainLocalStorage(),
                    redirectToURL: Self.callbackURL,
                    emitLocalSessionAsInitialSession: true
                )
            )
        )
    }

    // MARK: Accounts

    func currentUser() -> GroupUser? {
        client.auth.currentUser.map(Self.groupUser)
    }

    func signInWithGoogle() async throws -> GroupUser {
        do {
            // A web sheet run by Supabase: Google's own page, then back to the app.
            let session = try await client.auth.signInWithOAuth(provider: .google, redirectTo: Self.callbackURL)
            return Self.groupUser(session.user)
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            throw GroupError.cancelled
        } catch {
            throw Self.friendly(error)
        }
    }

    func signInWithApple(idToken: String, nonce: String, fullName: String?) async throws -> GroupUser {
        do {
            let session = try await client.auth.signInWithIdToken(
                credentials: OpenIDConnectCredentials(provider: .apple, idToken: idToken, nonce: nonce)
            )
            var user = Self.groupUser(session.user)
            if let fullName, !fullName.isEmpty {
                user.name = fullName
                try? await client.from("profiles")
                    .update(["display_name": String(fullName.prefix(40))])
                    .eq("id", value: session.user.id.uuidString)
                    .execute()
            }
            return user
        } catch {
            throw Self.friendly(error)
        }
    }

    /// Handles the link back from the web sheet, if it arrives as an ordinary link.
    func handle(_ url: URL) {
        client.auth.handle(url)
    }

    func signOut() async {
        try? await client.auth.signOut(scope: .local)
    }

    func deleteAccount() async throws {
        do {
            try await client.rpc("delete_my_account").execute()
        } catch {
            throw Self.friendly(error)
        }
        await signOut()
    }

    // MARK: Rounds

    func startRound(courseID: String, courseName: String, tee: String, playerName: String) async throws -> GroupRoundInfo {
        struct Params: Encodable {
            let p_course_id: String
            let p_course_name: String
            let p_tee: String
            let p_display_name: String
        }
        do {
            let row: RoundRow = try await client
                .rpc("start_group_round", params: Params(p_course_id: courseID, p_course_name: courseName, p_tee: tee, p_display_name: playerName))
                .execute()
                .value
            return row.info
        } catch {
            throw Self.friendly(error)
        }
    }

    func joinRound(code: String, playerName: String) async throws -> GroupRoundInfo {
        struct Params: Encodable {
            let p_code: String
            let p_display_name: String
        }
        do {
            let row: RoundRow = try await client
                .rpc("join_group_round", params: Params(p_code: code, p_display_name: playerName))
                .execute()
                .value
            return row.info
        } catch {
            throw Self.friendly(error)
        }
    }

    func fetch(roundID: String) async throws -> (players: [GroupPlayer], scores: [GroupScore]) {
        do {
            let players: [PlayerRow] = try await client.from("round_players")
                .select("user_id,seat,display_name")
                .eq("round_id", value: roundID)
                .execute()
                .value
            let scores: [ScoreRow] = try await client.from("scores")
                .select("user_id,hole,strokes")
                .eq("round_id", value: roundID)
                .execute()
                .value
            return (players.map(\.player), scores.map(\.score))
        } catch {
            throw Self.friendly(error)
        }
    }

    func send(strokes: [Int: Int], roundID: String) async throws {
        struct Row: Encodable {
            let round_id: String
            let user_id: String
            let hole: Int
            let strokes: Int
            let updated_at: String
        }
        guard let user = client.auth.currentUser else { throw GroupError.notSignedIn }
        let now = ISO8601DateFormatter().string(from: .now)
        let rows = strokes.keys.sorted().map {
            Row(round_id: roundID, user_id: user.id.uuidString, hole: $0, strokes: strokes[$0] ?? 0, updated_at: now)
        }
        guard !rows.isEmpty else { return }
        do {
            try await client.from("scores")
                .upsert(rows, onConflict: "round_id,user_id,hole", returning: .minimal)
                .execute()
        } catch {
            throw Self.friendly(error)
        }
    }

    func finish(roundID: String) async throws {
        do {
            try await client.rpc("finish_group_round", params: ["p_round": roundID]).execute()
        } catch {
            throw Self.friendly(error)
        }
    }

    func events(roundID: String) -> AsyncStream<GroupEvent> {
        let client = client
        let channel = client.channel("round-\(roundID)")
        let scores = channel.postgresChange(AnyAction.self, schema: "public", table: "scores", filter: .eq("round_id", value: roundID))
        let players = channel.postgresChange(InsertAction.self, schema: "public", table: "round_players", filter: .eq("round_id", value: roundID))
        return AsyncStream { continuation in
            let task = Task {
                do {
                    try await channel.subscribeWithError()
                } catch {
                    continuation.finish()
                    return
                }
                let decoder = JSONDecoder()
                await withTaskGroup(of: Void.self) { group in
                    group.addTask {
                        for await action in scores {
                            let row: ScoreRow?
                            switch action {
                            case .insert(let insert): row = try? insert.decodeRecord(as: ScoreRow.self, decoder: decoder)
                            case .update(let update): row = try? update.decodeRecord(as: ScoreRow.self, decoder: decoder)
                            case .delete: row = nil
                            }
                            if let row { continuation.yield(.score(row.score)) }
                        }
                    }
                    group.addTask {
                        for await insert in players {
                            if let row = try? insert.decodeRecord(as: PlayerRow.self, decoder: decoder) {
                                continuation.yield(.player(row.player))
                            }
                        }
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
                Task { await client.removeChannel(channel) }
            }
        }
    }

    // MARK: Rows

    private struct RoundRow: Decodable {
        let id: UUID
        let join_code: String
        let host_id: UUID?
        let course_id: String
        let course_name: String
        let tee: String
        let finished_at: String?

        var info: GroupRoundInfo {
            GroupRoundInfo(id: id.uuidString, code: join_code, courseID: course_id, courseName: course_name,
                           tee: tee, hostID: host_id?.uuidString, isFinished: finished_at != nil)
        }
    }

    private struct PlayerRow: Decodable {
        let user_id: UUID
        let seat: Int
        let display_name: String

        var player: GroupPlayer { GroupPlayer(userID: user_id.uuidString, seat: seat, name: display_name) }
    }

    private struct ScoreRow: Decodable {
        let user_id: UUID
        let hole: Int
        let strokes: Int

        var score: GroupScore { GroupScore(userID: user_id.uuidString, hole: hole, strokes: strokes) }
    }

    // MARK: Helpers

    private static func groupUser(_ user: User) -> GroupUser {
        let metadata = user.userMetadata
        let name = metadata["full_name"]?.stringValue ?? metadata["name"]?.stringValue ?? user.email ?? "Golfer"
        return GroupUser(id: user.id.uuidString, name: name)
    }

    /// The database's own reasons (see the migration's errcodes) in plain words.
    private static func friendly(_ error: Error) -> Error {
        if let error = error as? GroupError { return error }
        if let error = error as? PostgrestError {
            switch error.code ?? "" {
            case "GR001": return GroupError.noSuchRound
            case "GR002": return GroupError.roundFull
            case "GR003": return GroupError.notSignedIn
            case "GR004": return GroupError.tooManyToday
            default: return GroupError.failed(error.message)
            }
        }
        if (error as? URLError) != nil {
            return GroupError.failed("No connection. Check your signal and try again.")
        }
        return GroupError.failed(error.localizedDescription)
    }
}
