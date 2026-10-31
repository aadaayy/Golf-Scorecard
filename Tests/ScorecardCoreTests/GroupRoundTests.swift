import XCTest
@testable import ScorecardCore

final class GroupRoundTests: XCTestCase {
    func testCleanAndCheckCodes() {
        XCTAssertEqual(JoinCode.clean(" abc-234 "), "ABC234")
        XCTAssertEqual(JoinCode.clean("abc 234 567"), "ABC234")
        XCTAssertTrue(JoinCode.isValid("ABC234"))
        XCTAssertFalse(JoinCode.isValid("ABC23"), "too short")
        XCTAssertFalse(JoinCode.isValid("ABCIO1"), "I, O and 1 are never in a code")
        XCTAssertEqual(JoinCode.alphabet.count, 31)
        XCTAssertEqual(JoinCode.spaced("ABC234"), "ABC 234")
    }

    /// The alphabet the app checks against is the one the database makes codes from.
    func testAlphabetMatchesTheDatabase() throws {
        let migrations = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("supabase/migrations")
        let files = try FileManager.default.contentsOfDirectory(at: migrations, includingPropertiesForKeys: nil)
        let sql = try files.filter { $0.pathExtension == "sql" }.map { try String(contentsOf: $0, encoding: .utf8) }.joined()
        XCTAssertTrue(sql.contains("'\(String(JoinCode.alphabet))'"), "new_join_code() should use the same letters")
        XCTAssertTrue(sql.contains("seat between 0 and \(GroupCard.maxPlayers - 1)"), "the database should seat as many as the card")
    }

    func testJoinLinkRoundTrip() {
        let link = JoinCode.link(for: "ABC234")
        XCTAssertEqual(link.absoluteString, "golfscorecard://join?code=ABC234")
        XCTAssertEqual(JoinCode.code(in: link), "ABC234")
        XCTAssertEqual(JoinCode.code(in: URL(string: "golfscorecard://join?code=abc-234")!), "ABC234")
        XCTAssertNil(JoinCode.code(in: URL(string: "golfscorecard://join?code=nope")!))
        XCTAssertNil(JoinCode.code(in: URL(string: "golfscorecard://round?start=1&hole=2")!))
    }

    private func grid(_ rows: [[Int: Int]]) -> StrokeGrid {
        var grid = StrokeGrid(playerCount: rows.count)
        for (p, row) in rows.enumerated() {
            for (hole, strokes) in row { grid.setStrokes(strokes, player: p, hole: hole) }
        }
        return grid
    }

    func testFriendJoiningAddsARowAndKeepsScores() {
        var card = GroupCard(names: ["Alberto"], grid: grid([[1: 5, 2: 4]]), mySeat: 0)
        let players = [GroupPlayer(userID: "me", seat: 0, name: "Server name"), GroupPlayer(userID: "sam", seat: 1, name: "Sam")]
        card.apply(players: players)
        XCTAssertEqual(card.names, ["Alberto", "Sam"], "my own name stays as typed on this phone")
        XCTAssertEqual(card.grid.strokes(player: 0, hole: 1), 5)
        XCTAssertEqual(card.grid.strokes(player: 0, hole: 2), 4)
        XCTAssertEqual(card.grid.strokes(player: 1, hole: 1), 0)
    }

    func testSeatsPastTheEndAreNamedLaterAndCapped() {
        var card = GroupCard(names: ["Me"], grid: StrokeGrid(playerCount: 1), mySeat: 0)
        card.apply(players: [GroupPlayer(userID: "c", seat: 2, name: "Cam")])
        XCTAssertEqual(card.names, ["Me", "Player 2", "Cam"])
        card.apply(players: [GroupPlayer(userID: "x", seat: 7, name: "Too many")])
        XCTAssertEqual(card.names.count, GroupCard.maxPlayers)
    }

    func testOthersScoresArriveButMineStayMine() {
        var card = GroupCard(names: ["Sam", "Me"], grid: grid([[:], [1: 4]]), mySeat: 1)
        let players = [GroupPlayer(userID: "sam", seat: 0, name: "Sam"), GroupPlayer(userID: "me", seat: 1, name: "Me")]
        let changed = card.apply(scores: [
            GroupScore(userID: "sam", hole: 1, strokes: 6),
            GroupScore(userID: "me", hole: 1, strokes: 9),       // an old copy of mine: ignored
            GroupScore(userID: "stranger", hole: 1, strokes: 3), // not seated: ignored
            GroupScore(userID: "sam", hole: 19, strokes: 3),     // no such hole: ignored
        ], players: players)
        XCTAssertTrue(changed)
        XCTAssertEqual(card.grid.strokes(player: 0, hole: 1), 6)
        XCTAssertEqual(card.grid.strokes(player: 1, hole: 1), 4)
        XCTAssertFalse(card.apply(scores: [GroupScore(userID: "sam", hole: 1, strokes: 6)], players: players), "same score again changes nothing")
    }

    func testRejoiningFillsMyEmptyHoles() {
        var card = GroupCard(names: ["Sam", "Me"], grid: grid([[:], [2: 3]]), mySeat: 1)
        card.fillMine(from: [GroupScore(userID: "me", hole: 1, strokes: 5), GroupScore(userID: "me", hole: 2, strokes: 7)], myUserID: "me")
        XCTAssertEqual(card.grid.strokes(player: 1, hole: 1), 5, "an empty hole takes the score already sent")
        XCTAssertEqual(card.grid.strokes(player: 1, hole: 2), 3, "a score on this phone wins")
    }

    func testChangedHolesSinceLastSent() {
        let mine = grid([[:], [1: 5, 2: 4, 3: 0]])
        XCTAssertEqual(GroupCard.changedHoles(mine: mine, since: [1: 5, 3: 6], seat: 1), [2: 4, 3: 0])
        XCTAssertEqual(GroupCard.changedHoles(mine: mine, since: [1: 5, 2: 4], seat: 1), [:])
    }
}
