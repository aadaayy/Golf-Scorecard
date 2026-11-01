import SwiftUI
import UIKit

/// Which part of the card a pane shows.
enum CardPart {
    /// One nine at a time, with a Front 9 / Back 9 switch (the nine view).
    case switchable
    /// Only the front nine: the left half of the full card.
    case front
    /// Only the back nine, with the round's total: the right half of the full card.
    case back
}

/// The paper score card: holes across, players down, one nine at a time.
///
/// The full card view shows two of these side by side, the front nine and the
/// back nine, like a paper card opened flat (see `CardPart`).
///
/// The card grows and shrinks to fill its pane: cells widen to use the width
/// and rows grow to use the height, so an open iPhone Duo gets a big card and
/// a sideways iPhone still fits a whole nine on its half of the screen.
struct CardPane: View {
    @Bindable var round: Round
    let course: Course
    @Binding var selectedHole: Int
    @Binding var selectedPlayer: Int
    var part: CardPart = .switchable

    @State private var showingBackNine = false
    /// The back nine is showing: picked with the switch, or this pane is the back half.
    private var onBack: Bool { part == .back || (part == .switchable && showingBackNine) }
    /// The space the grid has between the Front 9/Back 9 switch and the score buttons.
    @State private var gridArea: CGSize = .zero
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.scoresLocked) private var scoresLocked
    @Environment(\.editableSeat) private var editableSeat

    /// The smallest cells still easy to read and tap, and the largest worth drawing.
    private static let minCell: CGFloat = 26
    private static let maxCell: CGFloat = 64
    private static let minLabel: CGFloat = 52

    private var totalsCount: Int { onBack ? 2 : 1 }
    /// Both halves of the full card size their cells as if they had two total
    /// columns, so the front and back nines draw at the same size.
    private var sizingTotals: Int { part == .switchable ? totalsCount : 2 }
    /// Total columns (OUT, IN, TOT) are wider, so four-digit yardages fit.
    private static let totalWidthFactor: CGFloat = 1.4
    /// A half of the full card on a sideways phone, where height is scarcest:
    /// no FRONT 9 / BACK 9 title and no handicap row, so a foursome fits.
    private var tightFullCard: Bool { part != .switchable && verticalSizeClass == .compact }
    private var hasHandicaps: Bool { !tightFullCard && course.holes.contains(where: { $0.handicap != nil }) }
    private var rowCount: Int { 2 + teeRows.count + (hasHandicaps ? 1 : 0) + round.players.count }

    /// Cell width, label width and row height that fill the grid's space.
    private var sizes: (cell: CGFloat, total: CGFloat, label: CGFloat, row: CGFloat) {
        let compact = verticalSizeClass == .compact
        guard gridArea.width > 0 else { return (36, 50, 88, compact ? 30 : 36) }
        let width = gridArea.width - 32  // the grid's side padding
        let columns = CGFloat(nineHoles.count) + CGFloat(sizingTotals) * Self.totalWidthFactor
        let cell = min(Self.maxCell, max(Self.minCell, width * 0.83 / columns)).rounded(.down)
        let total = (cell * Self.totalWidthFactor).rounded(.down)
        let used = cell * CGFloat(nineHoles.count) + total * CGFloat(sizingTotals)
        let label = min(max(88, cell * 2.4), max(Self.minLabel, width - used)).rounded(.down)
        let minRow: CGFloat = compact ? 28 : 34
        let maxRow = max(minRow, cell * 1.4)
        let row = min(maxRow, max(minRow, (gridArea.height - 2) / CGFloat(rowCount))).rounded(.down)
        return (cell, total, label, row)
    }

    /// Text sizes that follow the cells, so a big card has big numbers.
    private var numberSize: CGFloat { min(26, max(12, min(sizes.cell * 0.46, sizes.row * 0.5))) }
    private var labelSize: CGFloat { min(20, max(11, sizes.row * 0.38)) }

    private var nineHoles: [Hole] { onBack ? course.backNine : course.frontNine }
    private var nineRange: ClosedRange<Int> { onBack ? 10...18 : 1...9 }
    private var nineLabel: String { onBack ? "In" : "Out" }
    /// Whether the hole being scored is on this pane, so its + and − go here.
    private var holdsSelectedHole: Bool {
        switch part {
        case .switchable: true
        case .front: selectedHole <= 9
        case .back: selectedHole >= 10
        }
    }
    private var player: Int { min(selectedPlayer, max(round.players.count - 1, 0)) }

    var body: some View {
        VStack(spacing: verticalSizeClass == .compact ? 8 : 12) {
            if tightFullCard {
                EmptyView()
            } else if part != .switchable {
                Text(part == .back ? "BACK 9" : "FRONT 9")
                    .font(Book.title(20, relativeTo: .title3))
                    .accessibilityLabel(part == .back ? "Back 9" : "Front 9")
            } else if !course.backNine.isEmpty {
                Picker("Nine", selection: $showingBackNine) {
                    Text("Front 9").tag(false)
                    Text("Back 9").tag(true)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
            }

            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onGeometryChange(for: CGSize.self) { $0.size } action: { gridArea = $0 }
                .overlay {
                    ScrollView([.horizontal, .vertical]) {
                        grid.padding(.horizontal)
                            .frame(minWidth: gridArea.width)
                    }
                    .scrollBounceBehavior(.basedOnSize, axes: [.horizontal, .vertical])
                    .scrollIndicators(.hidden)
                    .fixedSize(horizontal: false, vertical: gridFits)
                }

            if part == .switchable {
                entryBar
            } else {
                fullCardFooter
            }
        }
        .padding(.vertical, verticalSizeClass == .compact ? 8 : 16)
        .paperBackground()
        .onAppear { showingBackNine = selectedHole >= 10 }
        .onChange(of: selectedHole) { _, hole in
            showingBackNine = hole >= 10
        }
        .onChange(of: showingBackNine) { _, back in
            if part == .switchable, back != (selectedHole >= 10) { selectedHole = back ? 10 : 1 }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(paneIdentifier)
    }

    private var paneIdentifier: String {
        switch part {
        case .switchable: "card-pane"
        case .front: "full-card-front"
        case .back: "full-card-back"
        }
    }

    /// The + and − for the selected player and hole (or a friend's score in a group round).
    @ViewBuilder
    private var entryBar: some View {
        if !scoresLocked, let editableSeat, player != editableSeat {
            // A friend's row in a group round: theirs to enter.
            FriendScoreBar(
                playerName: round.players.indices.contains(player) ? round.players[player] : "",
                hole: selectedHole,
                strokes: round.grid.strokes(player: player, hole: selectedHole)
            )
            .padding(.horizontal)
        } else if !scoresLocked {
            ScoreEntryBar(
                playerName: round.players.indices.contains(player) ? round.players[player] : "",
                hole: selectedHole,
                strokes: round.grid.strokes(player: player, hole: selectedHole),
                par: course.hole(selectedHole)?.par
            ) { newValue in
                var grid = round.grid
                grid.setStrokes(newValue, player: player, hole: selectedHole)
                round.grid = grid
            }
            .padding(.horizontal)
        }
    }

    /// Under each half of the full card: the + and − in the half with the hole
    /// being scored, and the round's totals in the other. Both halves keep the
    /// same room, so the two nines stay level.
    private var fullCardFooter: some View {
        ZStack {
            // Room for the taller of the two, never shown.
            ScoreEntryBar(playerName: " ", hole: 18, strokes: 0, par: 4) { _ in }
                .padding(.horizontal)
                .hidden()
                .accessibilityHidden(true)
            RoundTotalsBar(round: round, course: course)
                .padding(.horizontal)
                .hidden()
                .accessibilityHidden(true)
            if !scoresLocked && holdsSelectedHole {
                entryBar
            } else if part == .back || (!scoresLocked && !holdsSelectedHole) {
                RoundTotalsBar(round: round, course: course)
                    .padding(.horizontal)
            }
        }
    }

    /// Whether the whole grid fits its space, so it can sit centered instead of scrolling.
    private var gridFits: Bool { sizes.row * CGFloat(rowCount) + 2 <= gridArea.height }

    /// Tee rows to show: all of them like the paper card, or only the one being
    /// played when the phone is sideways and height is scarce.
    private var teeRows: [String] {
        verticalSizeClass == .compact ? course.tees.filter { $0 == round.tee } : course.tees
    }

    private var plain: RowStyle { RowStyle(band: Book.page, ink: Book.ink) }

    private var grid: some View {
        Grid(horizontalSpacing: 0, verticalSpacing: 0) {
            headerRow
            ForEach(teeRows, id: \.self) { tee in teeRow(tee) }
            if hasHandicaps { handicapRow }
            parRow
            ForEach(round.players.indices, id: \.self) { p in playerRow(p) }
        }
        .overlay(Rectangle().stroke(CardColors.edge, lineWidth: 1))
    }

    private var headerRow: some View {
        GridRow {
            rowLabel("HOLE", plain, bold: true)
            ForEach(nineHoles, id: \.number) { hole in
                Button {
                    selectedHole = hole.number
                } label: {
                    cell("\(hole.number)", hole.number == selectedHole ? plain.highlighted : plain, bold: true)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("hole-\(hole.number)")
            }
            cell(nineLabel.uppercased(), plain, bold: true, total: true)
            if onBack { cell("TOT", plain, bold: true, total: true) }
        }
    }

    private func teeRow(_ tee: String) -> some View {
        let played = tee == round.tee
        let style = TeeStyle.row(for: tee)
        return GridRow {
            rowLabel(tee.uppercased(), style, bold: played, marked: played && teeRows.count > 1)
                .accessibilityLabel("\(tee) tees\(played ? ", playing" : "")")
            ForEach(nineHoles, id: \.number) { hole in
                cell(hole.yards[tee].map(String.init) ?? "", style, bold: played)
            }
            cell("\(course.yards(tee: tee, holes: nineRange))", style, bold: played, total: true)
            if onBack { cell("\(course.yards(tee: tee, holes: 1...18))", style, bold: played, total: true) }
        }
    }

    private var handicapRow: some View {
        let style = CardColors.handicap
        return GridRow {
            rowLabel("HCP", style, bold: true)
                .accessibilityLabel("Handicap")
            ForEach(nineHoles, id: \.number) { hole in
                cell(course.handicap(hole: hole.number, tee: round.tee).map(String.init) ?? "", style, bold: true)
            }
            cell("", style, total: true)
            if onBack { cell("", style, total: true) }
        }
    }

    private var parRow: some View {
        let style = CardColors.par
        return GridRow {
            rowLabel("PAR", style, bold: true)
            ForEach(nineHoles, id: \.number) { hole in cell("\(hole.par)", style, bold: true) }
            cell("\(course.par(holes: nineRange))", style, bold: true, total: true)
            if onBack { cell("\(course.par(holes: 1...18))", style, bold: true, total: true) }
        }
    }

    private func playerRow(_ p: Int) -> some View {
        let strokes = round.grid
        return GridRow {
            rowLabel(round.players[p], plain, bold: true)
            ForEach(nineHoles, id: \.number) { hole in
                scoreCell(player: p, hole: hole.number, strokes: strokes)
            }
            cell("\(strokes.total(player: p, holes: nineRange))", plain, bold: true, large: true, total: true)
                .accessibilityIdentifier(nineTotalIdentifier(p))
            if onBack {
                cell("\(strokes.total(player: p, holes: 1...18))", plain, bold: true, large: true, total: true)
                    .accessibilityIdentifier("total-\(p)")
            }
        }
    }

    private func nineTotalIdentifier(_ p: Int) -> String {
        switch part {
        case .switchable: "nine-total-\(p)"
        case .front: "out-total-\(p)"
        case .back: "in-total-\(p)"
        }
    }

    private func scoreCell(player p: Int, hole: Int, strokes: StrokeGrid) -> some View {
        let value = strokes.strokes(player: p, hole: hole)
        let selected = p == player && hole == selectedHole
        return Button {
            selectedHole = hole
            selectedPlayer = p
        } label: {
            cell(value > 0 ? "\(value)" : "", selected ? plain.selected : plain, bold: true, large: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(round.players[p]), hole \(hole)")
        .accessibilityValue(value > 0 ? "\(value)" : "no score")
        .accessibilityIdentifier("score-\(p)-\(hole)")
    }

    private func rowLabel(_ text: String, _ style: RowStyle, bold: Bool = false, marked: Bool = false) -> some View {
        HStack(spacing: 3) {
            if marked {
                Image(systemName: "arrowtriangle.right.fill").font(.system(size: labelSize * 0.55))
            }
            Text(text)
                .font(Book.typewriter(labelSize * 1.08, bold: bold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .foregroundStyle(style.ink)
        .padding(.horizontal, 6)
        .frame(width: sizes.label, height: sizes.row, alignment: .leading)
        .background(style.band)
        .overlay(Rectangle().stroke(CardColors.line, lineWidth: 0.5))
    }

    private func cell(_ text: String, _ style: RowStyle, bold: Bool = false, large: Bool = false, total: Bool = false) -> some View {
        let size = large ? numberSize * 1.18 : numberSize
        return Text(text)
            .font(.system(size: size, weight: bold ? .semibold : .regular, design: .monospaced))
            .lineLimit(1)
            .minimumScaleFactor(0.55)
            .foregroundStyle(style.ink)
            .frame(width: total ? sizes.total : sizes.cell, height: sizes.row)
            .background(style.band)
            .overlay(Rectangle().stroke(CardColors.line, lineWidth: 0.5))
            .contentShape(Rectangle())
    }
}

/// A row's background band and text color.
struct RowStyle {
    let band: Color
    let ink: Color

    /// The hole being looked at, in the HOLE row.
    var highlighted: RowStyle { RowStyle(band: Book.markedRow, ink: Book.red) }
    /// The score cell the plus and minus buttons change.
    var selected: RowStyle { RowStyle(band: Color(red: 0.925, green: 0.800, blue: 0.741), ink: Book.ink) }
}

/// The card's ink: a solid ink band for par, a shaded band for the
/// stroke index, and ink rules, like a card printed in a yardage book.
enum CardColors {
    static let par = RowStyle(band: Book.ink, ink: Book.paper)
    static let handicap = RowStyle(band: Book.shade, ink: Book.ink)
    static let line = Book.ink.opacity(0.28)
    static let edge = Book.ink.opacity(0.85)
}

/// The colored band a tee's row gets, like the paper card.
enum TeeStyle {
    static func row(for tee: String) -> RowStyle {
        switch tee.lowercased() {
        // The card's tee colors, softened a little to sit on the paper.
        case "gold": RowStyle(band: Color(red: 0.82, green: 0.73, blue: 0.45), ink: Book.ink)
        case "blue": RowStyle(band: Color(red: 0.58, green: 0.72, blue: 0.85), ink: Book.ink)
        case "white": RowStyle(band: Book.page, ink: Book.ink)
        case "brown": RowStyle(band: Color(red: 0.38, green: 0.26, blue: 0.19), ink: Book.paper)
        case "red": RowStyle(band: Book.red, ink: Book.paper)
        case "black": RowStyle(band: Book.ink, ink: Book.paper)
        case "green": RowStyle(band: Book.leaf, ink: Book.paper)
        case "silver": RowStyle(band: Color(white: 0.78), ink: Book.ink)
        case "yellow": RowStyle(band: Color(red: 0.94, green: 0.84, blue: 0.42), ink: Book.ink)
        case "orange": RowStyle(band: Color(red: 0.90, green: 0.60, blue: 0.32), ink: Book.ink)
        default: RowStyle(band: Book.shade, ink: Book.ink)
        }
    }
}

/// Minus and plus buttons for the selected player and hole.
struct ScoreEntryBar: View {
    let playerName: String
    let hole: Int
    let strokes: Int
    let par: Int?
    var onChange: (Int) -> Void

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(playerName).font(Book.title(19, relativeTo: .headline))
                Text(par.map { "Hole \(hole) · Par \($0)" } ?? "Hole \(hole)")
                    .font(.subheadline)
                    .foregroundStyle(Book.pencil)
            }
            Spacer()
            Button {
                onChange(max(strokes - 1, 0))
            } label: {
                Image(systemName: "minus.circle.fill").font(.title)
            }
            .disabled(strokes == 0)
            .accessibilityLabel("One less stroke")
            .accessibilityIdentifier("score-minus")

            Text(strokes > 0 ? "\(strokes)" : "–")
                .font(.title.weight(.bold))
                .frame(minWidth: 40)
                .accessibilityIdentifier("score-value")

            Button {
                // The first tap jumps to par, which is the most common score.
                onChange(strokes == 0 ? (par ?? 1) : strokes + 1)
            } label: {
                Image(systemName: "plus.circle.fill").font(.title)
            }
            .disabled(strokes >= StrokeGrid.maxStrokes)
            .accessibilityLabel("One more stroke")
            .accessibilityIdentifier("score-plus")
        }
        .padding(12)
        .foregroundStyle(Book.ink)
        .bookBox()
    }
}

/// Each player's total so far and how it stands to par, beside the + and −
/// on the full card.
struct RoundTotalsBar: View {
    let round: Round
    let course: Course

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("TOTAL").font(Book.title(19, relativeTo: .headline))
                Text("Par \(course.par(holes: 1...18))")
                    .font(.subheadline)
                    .foregroundStyle(Book.pencil)
            }
            Spacer(minLength: 8)
            ForEach(round.players.indices, id: \.self) { p in
                VStack(spacing: 2) {
                    Text(round.players[p])
                        .font(.caption)
                        .foregroundStyle(Book.pencil)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(round.grid.total(player: p, holes: 1...18))")
                            .font(.title2.weight(.bold))
                            .accessibilityIdentifier("full-total-\(p)")
                        Text(toPar(p))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Book.red)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                }
                .frame(minWidth: 44)
            }
        }
        .padding(12)
        .foregroundStyle(Book.ink)
        .bookBox()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("round-totals")
    }

    /// Strokes against par on the holes scored so far: E, +3 or −1.
    private func toPar(_ p: Int) -> String {
        var over = 0
        var scored = false
        for hole in course.holes {
            let strokes = round.grid.strokes(player: p, hole: hole.number)
            guard strokes > 0 else { continue }
            scored = true
            over += strokes - hole.par
        }
        guard scored else { return "" }
        return over == 0 ? "E" : over > 0 ? "+\(over)" : "−\(-over)"
    }
}
