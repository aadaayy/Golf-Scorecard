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

    private var grid: some View {
        let strokes = round.grid
        return Grid(horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow {
                rowLabel("Hole")
                ForEach(nineHoles, id: \.number) { hole in
                    Button {
                        selectedHole = hole.number
                    } label: {
                        cell("\(hole.number)", bold: true)
                    }
                    .buttonStyle(.plain)
                    .background(hole.number == selectedHole ? Color.accentColor.opacity(0.15) : Color.clear)
                    .accessibilityIdentifier("hole-\(hole.number)")
                }
                cell(nineLabel, bold: true)
                if showingBackNine { cell("Tot", bold: true) }
            }
            GridRow {
                rowLabel("Par")
                ForEach(nineHoles, id: \.number) { cell("\($0.par)") }
                cell("\(course.par(holes: nineRange))")
                if showingBackNine { cell("\(course.par(holes: 1...18))") }
            }
            GridRow {
                rowLabel(round.tee)
                ForEach(nineHoles, id: \.number) { hole in
                    cell(hole.yards[round.tee].map(String.init) ?? "")
                }
                cell("\(course.yards(tee: round.tee, holes: nineRange))")
                if showingBackNine { cell("\(course.yards(tee: round.tee, holes: 1...18))") }
            }
            ForEach(round.players.indices, id: \.self) { p in
                GridRow {
                    rowLabel(round.players[p])
                    ForEach(nineHoles, id: \.number) { hole in
                        let value = strokes.strokes(player: p, hole: hole.number)
                        Button {
                            selectedHole = hole.number
                            selectedPlayer = p
                        } label: {
                            cell(value > 0 ? "\(value)" : "", bold: true)
                        }
                        .buttonStyle(.plain)
                        .background(p == player && hole.number == selectedHole ? Color.accentColor.opacity(0.3) : Color.clear)
                        .accessibilityLabel("\(round.players[p]), hole \(hole.number)")
                        .accessibilityValue(value > 0 ? "\(value)" : "no score")
                        .accessibilityIdentifier("score-\(p)-\(hole.number)")
                    }
                    cell("\(strokes.total(player: p, holes: nineRange))", bold: true)
                        .accessibilityIdentifier("nine-total-\(p)")
                    if showingBackNine {
                        cell("\(strokes.total(player: p, holes: 1...18))", bold: true)
                            .accessibilityIdentifier("total-\(p)")
                    }
                }
            }
        }
    }

    private func rowLabel(_ text: String) -> some View {
        Text(text)
            .font(sizes.cell < Self.fullCell ? .footnote : .subheadline)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 6)
            .frame(width: sizes.label, height: rowHeight, alignment: .leading)
            .overlay(Rectangle().stroke(Color.secondary.opacity(0.3), lineWidth: 0.5))
    }

    private func cell(_ text: String, bold: Bool = false) -> some View {
        let font: Font = sizes.cell < Self.fullCell ? .footnote : .subheadline
        return Text(text)
            .font(bold ? font.weight(.semibold) : font)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(width: sizes.cell, height: rowHeight)
            .overlay(Rectangle().stroke(Color.secondary.opacity(0.3), lineWidth: 0.5))
            .contentShape(Rectangle())
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
