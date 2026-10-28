import SwiftUI

/// The nine view's right half: every hole of the nine being played, like the
/// strip of drawings across the top of a paper card. Tap one to go to it.
struct NinePane: View {
    let course: Course
    let tee: String
    @Binding var selectedHole: Int

    @State private var area: CGSize = .zero
    private static let gap: CGFloat = 8
    /// Room under each drawing for its number, par and yards.
    private static let labelHeight: CGFloat = 52

    private var onBackNine: Bool { selectedHole >= 10 && !course.backNine.isEmpty }
    private var holes: [Hole] { onBackNine ? course.backNine : course.frontNine }
    private var range: ClosedRange<Int> { onBackNine ? 10...18 : 1...9 }

    var body: some View {
        VStack(spacing: 8) {
            VStack(spacing: 2) {
                Text(onBackNine ? "Back 9" : "Front 9").font(.title2.bold())
                Text("Par \(course.par(holes: range)) · \(course.yards(tee: tee, holes: range)) yds")
                    .foregroundStyle(.secondary)
            }
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onGeometryChange(for: CGSize.self) { $0.size } action: { area = $0 }
                .overlay { tiles }
        }
        .padding(12)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("nine-pane")
    }

    /// One, two or three rows, whichever draws the holes biggest.
    private var rowCount: Int {
        guard area.width > 0, !holes.isEmpty else { return 1 }
        var best = (rows: 1, drawn: CGFloat(0))
        for rows in 1...3 {
            let size = cellSize(rows: rows)
            let drawingHeight = size.height - Self.labelHeight
            guard drawingHeight > 40, size.width > 30 else { continue }
            var drawn: CGFloat = 0
            for hole in holes {
                let aspect = HoleDrawing.aspect(of: hole)
                let width = min(size.width - 8, drawingHeight * aspect)
                drawn += width * width / aspect
            }
            if drawn > best.drawn { best = (rows, drawn) }
        }
        return best.rows
    }

    private func cellSize(rows: Int) -> CGSize {
        let columns = Int((Double(holes.count) / Double(rows)).rounded(.up))
        let width = (area.width - Self.gap * CGFloat(columns - 1)) / CGFloat(columns)
        let height = (area.height - Self.gap * CGFloat(rows - 1)) / CGFloat(rows)
        return CGSize(width: max(width, 0), height: max(height, 0))
    }

    private var tiles: some View {
        let rows = rowCount
        let columns = Int((Double(holes.count) / Double(rows)).rounded(.up))
        let size = cellSize(rows: rows)
        return VStack(spacing: Self.gap) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: Self.gap) {
                    ForEach(holes.dropFirst(row * columns).prefix(columns), id: \.number) { hole in
                        tile(hole).frame(width: size.width, height: size.height)
                    }
                }
            }
        }
    }

    private func tile(_ hole: Hole) -> some View {
        let selected = hole.number == selectedHole
        return Button {
            selectedHole = hole.number
        } label: {
            VStack(spacing: 4) {
                HoleDrawing(hole: hole)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                VStack(spacing: 0) {
                    Text("\(hole.number)").font(.headline)
                    Text("Par \(hole.par)").font(.caption)
                    if let yards = hole.yards[tee] {
                        Text("\(yards)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(height: Self.labelHeight - 4)
            }
            .padding(4)
            .background(selected ? Color.accentColor.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? Color.accentColor : .clear, lineWidth: 2))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Hole \(hole.number), par \(hole.par)")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("nine-hole-\(hole.number)")
    }
}
