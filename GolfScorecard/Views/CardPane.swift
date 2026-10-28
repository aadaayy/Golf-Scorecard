import SwiftUI
import UIKit

/// The paper score card: holes across, players down, one nine at a time.
///
/// The card grows and shrinks to fill its pane: cells widen to use the width
/// and rows grow to use the height, so an open iPhone Duo gets a big card and
/// a sideways iPhone still fits a whole nine on its half of the screen.
struct CardPane: View {
    @Bindable var round: Round
    let course: Course
    @Binding var selectedHole: Int
    @Binding var selectedPlayer: Int

    @State private var showingBackNine = false
    /// The space the grid has between the Front 9/Back 9 switch and the score buttons.
    @State private var gridArea: CGSize = .zero
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.scoresLocked) private var scoresLocked

    /// The smallest cells still easy to read and tap, and the largest worth drawing.
    private static let minCell: CGFloat = 26
    private static let maxCell: CGFloat = 64
    private static let minLabel: CGFloat = 52

    private var totalsCount: Int { showingBackNine ? 2 : 1 }
    /// Total columns (OUT, IN, TOT) are wider, so four-digit yardages fit.
    private static let totalWidthFactor: CGFloat = 1.4
    private var hasHandicaps: Bool { course.holes.contains(where: { $0.handicap != nil }) }
    private var rowCount: Int { 2 + teeRows.count + (hasHandicaps ? 1 : 0) + round.players.count }

    /// Cell width, label width and row height that fill the grid's space.
    private var sizes: (cell: CGFloat, total: CGFloat, label: CGFloat, row: CGFloat) {
        let compact = verticalSizeClass == .compact
        guard gridArea.width > 0 else { return (36, 50, 88, compact ? 30 : 36) }
        let width = gridArea.width - 32  // the grid's side padding
        let columns = CGFloat(nineHoles.count) + CGFloat(totalsCount) * Self.totalWidthFactor
        let cell = min(Self.maxCell, max(Self.minCell, width * 0.83 / columns)).rounded(.down)
        let total = (cell * Self.totalWidthFactor).rounded(.down)
        let used = cell * CGFloat(nineHoles.count) + total * CGFloat(totalsCount)
        let label = min(max(88, cell * 2.4), max(Self.minLabel, width - used)).rounded(.down)
        let minRow: CGFloat = compact ? 28 : 34
        let maxRow = max(minRow, cell * 1.4)
        let row = min(maxRow, max(minRow, (gridArea.height - 2) / CGFloat(rowCount))).rounded(.down)
        return (cell, total, label, row)
    }

    /// Text sizes that follow the cells, so a big card has big numbers.
    private var numberSize: CGFloat { min(26, max(12, min(sizes.cell * 0.46, sizes.row * 0.5))) }
    private var labelSize: CGFloat { min(20, max(11, sizes.row * 0.38)) }

    private var nineHoles: [Hole] { showingBackNine ? course.backNine : course.frontNine }
    private var nineRange: ClosedRange<Int> { showingBackNine ? 10...18 : 1...9 }
    private var nineLabel: String { showingBackNine ? "In" : "Out" }
    private var player: Int { min(selectedPlayer, max(round.players.count - 1, 0)) }

    var body: some View {
        VStack(spacing: verticalSizeClass == .compact ? 8 : 12) {
            if !course.backNine.isEmpty {
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

            if !scoresLocked {
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
        .padding(.vertical, verticalSizeClass == .compact ? 8 : 16)
        .onAppear { showingBackNine = selectedHole >= 10 }
        .onChange(of: selectedHole) { _, hole in
            showingBackNine = hole >= 10
        }
        .onChange(of: showingBackNine) { _, back in
            if back != (selectedHole >= 10) { selectedHole = back ? 10 : 1 }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("card-pane")
    }

    /// Whether the whole grid fits its space, so it can sit centered instead of scrolling.
    private var gridFits: Bool { sizes.row * CGFloat(rowCount) + 2 <= gridArea.height }

    /// Tee rows to show: all of them like the paper card, or only the one being
    /// played when the phone is sideways and height is scarce.
    private var teeRows: [String] {
        verticalSizeClass == .compact ? [round.tee] : course.tees
    }

    private var plain: RowStyle { RowStyle(band: Color(.systemBackground), ink: .primary) }

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
            if showingBackNine { cell("TOT", plain, bold: true, total: true) }
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
            if showingBackNine { cell("\(course.yards(tee: tee, holes: 1...18))", style, bold: played, total: true) }
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
            if showingBackNine { cell("", style, total: true) }
        }
    }

    private var parRow: some View {
        let style = CardColors.par
        return GridRow {
            rowLabel("PAR", style, bold: true)
            ForEach(nineHoles, id: \.number) { hole in cell("\(hole.par)", style, bold: true) }
            cell("\(course.par(holes: nineRange))", style, bold: true, total: true)
            if showingBackNine { cell("\(course.par(holes: 1...18))", style, bold: true, total: true) }
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
                .accessibilityIdentifier("nine-total-\(p)")
            if showingBackNine {
                cell("\(strokes.total(player: p, holes: 1...18))", plain, bold: true, large: true, total: true)
                    .accessibilityIdentifier("total-\(p)")
            }
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
                .font(.system(size: labelSize, weight: bold ? .bold : .regular, design: .serif))
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
            .font(.system(size: size, weight: bold ? .semibold : .regular))
            .monospacedDigit()
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
    var highlighted: RowStyle { RowStyle(band: Color.accentColor.opacity(0.2), ink: ink) }
    /// The score cell the plus and minus buttons change.
    var selected: RowStyle { RowStyle(band: Color.accentColor.opacity(0.32), ink: ink) }
}

/// Colors borrowed from paper scorecards.
enum CardColors {
    static let par = RowStyle(band: Color(red: 0.36, green: 0.38, blue: 0.37), ink: .white)
    static let handicap = RowStyle(band: Color(red: 0.96, green: 0.86, blue: 0.62), ink: Color(red: 0.25, green: 0.2, blue: 0.1))
    static let line = Color.secondary.opacity(0.35)
    static let edge = Color.secondary.opacity(0.6)
}

/// The colored band a tee's row gets, like the paper card.
enum TeeStyle {
    static func row(for tee: String) -> RowStyle {
        switch tee.lowercased() {
        case "gold": RowStyle(band: Color(red: 0.80, green: 0.72, blue: 0.40), ink: .black)
        case "blue": RowStyle(band: Color(red: 0.49, green: 0.70, blue: 0.89), ink: .black)
        case "white": RowStyle(band: Color(white: 0.97), ink: .black)
        case "brown": RowStyle(band: Color(red: 0.36, green: 0.23, blue: 0.16), ink: .white)
        case "red": RowStyle(band: Color(red: 0.85, green: 0.16, blue: 0.20), ink: .white)
        case "black": RowStyle(band: Color(white: 0.12), ink: .white)
        case "green": RowStyle(band: Color(red: 0.20, green: 0.55, blue: 0.30), ink: .white)
        case "silver": RowStyle(band: Color(white: 0.75), ink: .black)
        case "yellow": RowStyle(band: Color(red: 0.98, green: 0.85, blue: 0.30), ink: .black)
        case "orange": RowStyle(band: Color(red: 0.96, green: 0.55, blue: 0.20), ink: .black)
        default: RowStyle(band: Color(.secondarySystemBackground), ink: .primary)
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
                Text(playerName).font(.headline)
                Text(par.map { "Hole \(hole) · Par \($0)" } ?? "Hole \(hole)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
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
                .font(.title.monospacedDigit())
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
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }
}
