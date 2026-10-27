import SwiftUI

/// The paper score card: holes across, players down, one nine at a time.
///
/// Cells shrink to fit the pane, so a whole nine and its total fit on the
/// half of the screen a sideways iPhone gives the card.
struct CardPane: View {
    @Bindable var round: Round
    let course: Course
    @Binding var selectedHole: Int
    @Binding var selectedPlayer: Int

    @State private var showingBackNine = false
    @State private var paneWidth: CGFloat = 0
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    /// Full size cells, used whenever they fit.
    private static let fullCell: CGFloat = 36
    private static let fullLabel: CGFloat = 88
    /// The smallest cells still easy to read and tap.
    private static let minCell: CGFloat = 26
    private static let minLabel: CGFloat = 52

    private var columnCount: Int { nineHoles.count + (showingBackNine ? 2 : 1) }

    /// Cell and label widths that fit the pane, from full size down to the minimum.
    private var sizes: (cell: CGFloat, label: CGFloat) {
        let available = paneWidth - 32  // the grid's side padding
        let full = Self.fullLabel + Self.fullCell * CGFloat(columnCount)
        guard paneWidth > 0, available < full else { return (Self.fullCell, Self.fullLabel) }
        let label = max(Self.minLabel, min(Self.fullLabel, available * 0.17))
        let cell = max(Self.minCell, min(Self.fullCell, (available - label) / CGFloat(columnCount)))
        return (cell.rounded(.down), label.rounded(.down))
    }
    /// Shorter rows when the phone is sideways and height is scarce.
    private var rowHeight: CGFloat { verticalSizeClass == .compact ? 30 : 36 }

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

            ScrollView(.horizontal) {
                grid.padding(.horizontal)
            }

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

            Spacer(minLength: 0)
        }
        .padding(.vertical, verticalSizeClass == .compact ? 8 : 16)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { paneWidth = $0 }
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

    /// Tee rows to show: all of them like the paper card, or only the one being
    /// played when the phone is sideways and height is scarce.
    private var teeRows: [String] {
        verticalSizeClass == .compact ? [round.tee] : course.tees
    }

    private var grid: some View {
        let strokes = round.grid
        let plain = RowStyle(band: Color(.systemBackground), ink: .primary)
        return Grid(horizontalSpacing: 0, verticalSpacing: 0) {
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
                cell(nineLabel.uppercased(), plain, bold: true)
                if showingBackNine { cell("TOT", plain, bold: true) }
            }
            ForEach(teeRows, id: \.self) { tee in
                let played = tee == round.tee
                let style = TeeStyle.row(for: tee)
                GridRow {
                    rowLabel(tee.uppercased(), style, bold: played, marked: played && teeRows.count > 1)
                        .accessibilityLabel("\(tee) tees\(played ? ", playing" : "")")
                    ForEach(nineHoles, id: \.number) { hole in
                        cell(hole.yards[tee].map(String.init) ?? "", style, bold: played)
                    }
                    cell("\(course.yards(tee: tee, holes: nineRange))", style, bold: played)
                    if showingBackNine { cell("\(course.yards(tee: tee, holes: 1...18))", style, bold: played) }
                }
            }
            if course.holes.contains(where: { $0.handicap != nil }) {
                GridRow {
                    rowLabel("HCP", CardColors.handicap, bold: true)
                        .accessibilityLabel("Handicap")
                    ForEach(nineHoles, id: \.number) { hole in
                        cell(course.handicap(hole: hole.number, tee: round.tee).map(String.init) ?? "", CardColors.handicap, bold: true)
                    }
                    cell("", CardColors.handicap)
                    if showingBackNine { cell("", CardColors.handicap) }
                }
            }
            GridRow {
                rowLabel("PAR", CardColors.par, bold: true)
                ForEach(nineHoles, id: \.number) { cell("\($0.par)", CardColors.par, bold: true) }
                cell("\(course.par(holes: nineRange))", CardColors.par, bold: true)
                if showingBackNine { cell("\(course.par(holes: 1...18))", CardColors.par, bold: true) }
            }
            ForEach(round.players.indices, id: \.self) { p in
                GridRow {
                    rowLabel(round.players[p], plain, bold: true)
                    ForEach(nineHoles, id: \.number) { hole in
                        let value = strokes.strokes(player: p, hole: hole.number)
                        let selected = p == player && hole.number == selectedHole
                        Button {
                            selectedHole = hole.number
                            selectedPlayer = p
                        } label: {
                            cell(value > 0 ? "\(value)" : "", selected ? plain.selected : plain, bold: true, large: true)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(round.players[p]), hole \(hole.number)")
                        .accessibilityValue(value > 0 ? "\(value)" : "no score")
                        .accessibilityIdentifier("score-\(p)-\(hole.number)")
                    }
                    cell("\(strokes.total(player: p, holes: nineRange))", plain, bold: true, large: true)
                        .accessibilityIdentifier("nine-total-\(p)")
                    if showingBackNine {
                        cell("\(strokes.total(player: p, holes: 1...18))", plain, bold: true, large: true)
                            .accessibilityIdentifier("total-\(p)")
                    }
                }
            }
        }
        .overlay(Rectangle().stroke(CardColors.edge, lineWidth: 1))
    }

    private func rowLabel(_ text: String, _ style: RowStyle, bold: Bool = false, marked: Bool = false) -> some View {
        HStack(spacing: 3) {
            if marked {
                Image(systemName: "arrowtriangle.right.fill").font(.system(size: 7))
            }
            Text(text)
                .font(.system(sizes.cell < Self.fullCell ? .caption : .footnote, design: .serif).weight(bold ? .bold : .regular))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .foregroundStyle(style.ink)
        .padding(.horizontal, 6)
        .frame(width: sizes.label, height: rowHeight, alignment: .leading)
        .background(style.band)
        .overlay(Rectangle().stroke(CardColors.line, lineWidth: 0.5))
    }

    private func cell(_ text: String, _ style: RowStyle, bold: Bool = false, large: Bool = false) -> some View {
        let base: Font = sizes.cell < Self.fullCell ? .footnote : .subheadline
        let font: Font = large ? (sizes.cell < Self.fullCell ? .subheadline : .body) : base
        return Text(text)
            .font(bold ? font.weight(.semibold) : font)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.55)
            .foregroundStyle(style.ink)
            .frame(width: sizes.cell, height: rowHeight)
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
