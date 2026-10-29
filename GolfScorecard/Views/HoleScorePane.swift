import SwiftUI

/// The hole view's left half: just the score for the hole you're on, big
/// enough to read and change at a glance.
struct HoleScorePane: View {
    @Bindable var round: Round
    let course: Course
    @Binding var selectedHole: Int
    @Environment(\.scoresLocked) private var scoresLocked

    private var hole: Hole? { course.hole(selectedHole) }

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 2) {
                Text("Hole \(selectedHole)").font(.largeTitle.bold())
                if let hole {
                    Text("Par \(hole.par)").font(.title3).foregroundStyle(.secondary)
                }
            }
            ForEach(round.players.indices, id: \.self) { p in
                playerScore(p)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 20))
            }
        }
        .padding()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("hole-score-pane")
    }

    /// Bigger numbers when there are fewer players to fit.
    private var numberSize: CGFloat {
        switch round.players.count {
        case 1: 120
        case 2: 84
        default: 56
        }
    }

    private func playerScore(_ p: Int) -> some View {
        let grid = round.grid
        let strokes = grid.strokes(player: p, hole: selectedHole)
        let par = hole?.par
        let nine = selectedHole >= 10 ? 10...18 : 1...9
        let buttonSize = min(64, numberSize * 0.55)
        return VStack(spacing: 8) {
            if round.players.count > 1 {
                Text(round.players[p]).font(.title2.weight(.semibold))
            }
            HStack(spacing: 12) {
                Button {
                    set(max(strokes - 1, 0), player: p)
                } label: {
                    Image(systemName: "minus.circle.fill").font(.system(size: buttonSize))
                }
                .disabled(strokes == 0)
                .opacity(scoresLocked ? 0 : 1)
                .disabled(scoresLocked)
                .accessibilityLabel("One less stroke")
                .accessibilityIdentifier("hole-score-minus-\(p)")

                // One line always: 10 and up shrink to fit rather than wrap.
                Text(strokes > 0 ? "\(strokes)" : "–")
                    .font(.system(size: numberSize, weight: .bold, design: .rounded).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .frame(minWidth: numberSize * 0.7, maxWidth: .infinity)
                    .layoutPriority(1)
                    .accessibilityIdentifier("hole-score-value-\(p)")

                Button {
                    // The first tap jumps to par, which is the most common score.
                    set(strokes == 0 ? (par ?? 1) : strokes + 1, player: p)
                } label: {
                    Image(systemName: "plus.circle.fill").font(.system(size: buttonSize))
                }
                .disabled(strokes >= StrokeGrid.maxStrokes)
                .opacity(scoresLocked ? 0 : 1)
                .disabled(scoresLocked)
                .accessibilityLabel("One more stroke")
                .accessibilityIdentifier("hole-score-plus-\(p)")
            }
            Text(strokes > 0 && par != nil ? Self.scoreName(strokes: strokes, par: par!) : " ")
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)
            Text(totals(player: p, grid: grid, nine: nine))
                .font(.headline.monospacedDigit())
                .accessibilityIdentifier("hole-total-\(p)")
        }
        .padding()
    }

    private func set(_ value: Int, player p: Int) {
        var grid = round.grid
        grid.setStrokes(value, player: p, hole: selectedHole)
        round.grid = grid
    }

    /// "Out 41 · Total 41 · +5", counting only holes with a score for the
    /// score against par.
    private func totals(player p: Int, grid: StrokeGrid, nine: ClosedRange<Int>) -> String {
        let nineTotal = grid.total(player: p, holes: nine)
        let total = grid.total(player: p, holes: 1...18)
        var toPar = 0
        for hole in course.holes {
            let strokes = grid.strokes(player: p, hole: hole.number)
            if strokes > 0 { toPar += strokes - hole.par }
        }
        let parText = toPar == 0 ? "Even" : (toPar > 0 ? "+\(toPar)" : "\(toPar)")
        let nineName = nine.lowerBound == 1 ? "Out" : "In"
        return "\(nineName) \(nineTotal) · Total \(total) · \(parText)"
    }

    static func scoreName(strokes: Int, par: Int) -> String {
        if strokes == 1 { return "Hole in one" }
        switch strokes - par {
        case ...(-3): return "Albatross"
        case -2: return "Eagle"
        case -1: return "Birdie"
        case 0: return "Par"
        case 1: return "Bogey"
        case 2: return "Double bogey"
        case 3: return "Triple bogey"
        case let over: return "+\(over)"
        }
    }
}
