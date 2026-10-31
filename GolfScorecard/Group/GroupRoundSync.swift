import Foundation
import Observation

/// Keeps one group round's card live while it's open: friends' rows fill in
/// as they score, new friends get a row, and this phone's own scores go out
/// as they're entered.
///
/// Without a signal the round carries on as normal; scores entered meanwhile
/// go out when the connection is back.
@MainActor
@Observable
final class GroupRoundSync {
    enum Status: Equatable {
        case connecting
        case live
        /// No connection right now, or scores waiting to go out.
        case offline
    }

    private(set) var status = Status.connecting
    /// Everyone in the round as the group last said, for the bar above the card.
    private(set) var players: [GroupPlayer] = []

    @ObservationIgnored private let round: Round
    @ObservationIgnored private let service: GroupService
    @ObservationIgnored private let myUserID: String
    /// This phone's strokes by hole, as last sent and accepted.
    @ObservationIgnored private var sent: [Int: Int] = [:]
    @ObservationIgnored private var sending = false
    @ObservationIgnored private var sendAgain = false
    @ObservationIgnored private var task: Task<Void, Never>?

    /// How often the whole round is read again while open, in case a live
    /// update was missed. Cheap: two small reads.
    private static let refreshEvery: Duration = .seconds(30)
    private static let retryAfter: Duration = .seconds(5)

    init(round: Round, service: GroupService, myUserID: String) {
        self.round = round
        self.service = service
        self.myUserID = myUserID
    }

    var roundID: String? { round.groupRoundID }

    func start() {
        guard task == nil, let roundID = round.groupRoundID else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.runLive(roundID: roundID)
                guard !Task.isCancelled else { return }
                self?.status = .offline
                try? await Task.sleep(for: Self.retryAfter)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    /// Reads the whole round, then listens until the connection drops.
    private func runLive(roundID: String) async {
        let events = service.events(roundID: roundID)
        do {
            try await refresh(roundID: roundID, firstTime: status == .connecting)
        } catch {
            return
        }
        status = .live
        await sendChanges()
        await withTaskGroup(of: Void.self) { group in
            group.addTask { @MainActor [weak self] in
                for await event in events {
                    self?.apply(event)
                }
            }
            group.addTask { @MainActor [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: Self.refreshEvery)
                    guard let self, !Task.isCancelled else { return }
                    try? await self.refresh(roundID: roundID, firstTime: false)
                    await self.sendChanges()
                }
            }
            // When the live updates stop, the connection is gone: start again.
            _ = await group.next()
            group.cancelAll()
        }
    }

    private func refresh(roundID: String, firstTime: Bool) async throws {
        let state = try await service.fetch(roundID: roundID)
        players = state.players
        if firstTime {
            sent = Dictionary(state.scores.filter { $0.userID == myUserID }.map { ($0.hole, $0.strokes) },
                              uniquingKeysWith: { _, last in last })
        }
        update { card in
            card.apply(players: state.players)
            card.apply(scores: state.scores, players: state.players)
            if firstTime { card.fillMine(from: state.scores, myUserID: myUserID) }
        }
    }

    private func apply(_ event: GroupEvent) {
        switch event {
        case .player(let player):
            players.removeAll { $0.userID == player.userID }
            players.append(player)
            players.sort { $0.seat < $1.seat }
            update { $0.apply(players: players) }
        case .score(let score):
            update { $0.apply(scores: [score], players: players) }
        }
    }

    /// Changes the round's card, keeping this phone's own name as typed here.
    private func update(_ change: (inout GroupCard) -> Void) {
        var card = GroupCard(names: round.players, grid: round.grid, mySeat: round.groupSeat)
        change(&card)
        if card.names != round.players { round.players = card.names }
        if card.grid.values != round.strokes { round.strokes = card.grid.values }
    }

    /// Sends this phone's scores that changed since they were last sent.
    /// Called whenever the card changes; a no-op when nothing of ours did.
    func sendChanges() async {
        guard let roundID = round.groupRoundID else { return }
        guard !sending else {
            sendAgain = true
            return
        }
        let changes = GroupCard.changedHoles(mine: round.grid, since: sent, seat: round.groupSeat)
        guard !changes.isEmpty else { return }
        sending = true
        defer { sending = false }
        do {
            try await service.send(strokes: changes, roundID: roundID)
            sent.merge(changes) { _, new in new }
            if status == .offline, task != nil { status = .live }
        } catch {
            status = .offline
            return
        }
        if sendAgain {
            sendAgain = false
            sending = false
            await sendChanges()
        }
    }

    /// Closes the round to new players, when the host finishes. Best effort.
    func finishRound() {
        guard round.groupIsHost, let roundID = round.groupRoundID else { return }
        let service = service
        Task { try? await service.finish(roundID: roundID) }
    }
}
