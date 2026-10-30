import SwiftUI

/// The end of a round: each player's Out, In, Total and score to par, like the
/// totals column of a paper card. Save marks the round finished; without
/// `onSave` (a round already finished) it's just a look back.
struct RoundSummaryView: View {
    let round: Round
    let course: Course
    var onSave: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    RoundTotals(round: round, course: course)
                    if onSave != nil, holesMissing > 0 {
                        Text("\(holesMissing) holes have no score yet. You can still save; the totals count the holes you scored.")
                            .font(.footnote)
                            .foregroundStyle(Book.pencil)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding()
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .paperBackground()
            .navigationTitle(onSave == nil ? "Summary" : "Finish round")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let onSave {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Keep Playing") { dismiss() }
                            .accessibilityIdentifier("keep-playing")
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save Round", action: onSave)
                            .fontWeight(.semibold)
                            .accessibilityIdentifier("save-round")
                    }
                } else {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
            }
        }
    }

    /// Holes the first player hasn't scored, out of the course's holes.
    private var holesMissing: Int {
        course.holes.count - round.grid.holesPlayed(player: 0, holes: 1...course.holes.count)
    }

    static func toParText(_ value: Int) -> String {
        value == 0 ? "Even" : (value > 0 ? "+\(value)" : "\(value)")
    }
}

/// The course and date, then each player's Out, In, Total, to par and (for
/// the first player, with a handicap) net. Used by the summary and by Past
/// Rounds on a wide screen.
struct RoundTotals: View {
    let round: Round
    let course: Course

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 4) {
                Text(round.courseName).font(Book.title(24, relativeTo: .title2)).multilineTextAlignment(.center)
                Text("\(round.date.formatted(date: .abbreviated, time: .omitted))\(round.tee.isEmpty ? "" : " · \(round.tee) tees") · Par \(course.par(holes: 1...18))")
                    .foregroundStyle(Book.pencil)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 8)

            ForEach(round.players.indices, id: \.self) { p in
                playerCard(p)
            }
        }
    }

    private func playerCard(_ p: Int) -> some View {
        let grid = round.grid
        let out = grid.total(player: p, holes: 1...9)
        let inn = grid.total(player: p, holes: 10...18)
        let total = grid.total(player: p, holes: 1...18)
        let played = grid.holesPlayed(player: p, holes: 1...18)
        return VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(round.players[p]).font(Book.title(21, relativeTo: .title3))
                Spacer()
                if played > 0 && played < course.holes.count {
                    Text("Thru \(played)").foregroundStyle(Book.pencil)
                }
            }
            HStack(spacing: 0) {
                figure("Out", out > 0 ? "\(out)" : "–")
                figure("In", inn > 0 ? "\(inn)" : "–")
                figure("Total", total > 0 ? "\(total)" : "–", big: true)
                    .accessibilityIdentifier("summary-total-\(p)")
                figure("To par", grid.toPar(player: p, course: course).map(RoundSummaryView.toParText) ?? "–")
                if p == 0, let net = netScore(total: total, played: played) {
                    figure("Net", "\(net)")
                        .accessibilityIdentifier("summary-net")
                }
            }
        }
        .padding()
        .bookBox(cornerRadius: 16)
    }

    /// Gross minus handicap strokes, for a full round or a full nine.
    private func netScore(total: Int, played: Int) -> Int? {
        guard let index = round.playerHandicap,
              let strokes = HandicapIndex.strokes(index: index, holesPlayed: played) else { return nil }
        return total - strokes
    }

    private func figure(_ label: String, _ value: String, big: Bool = false) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: big ? 40 : 26, weight: .bold, design: .monospaced))
                .foregroundStyle(big ? Book.red : Book.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(Book.pencil)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}
