import SwiftUI
import UIKit

/// The hole map for the selected hole, with previous and next buttons.
///
/// The drawing fills the pane's height. Most holes are long and thin, so when
/// that leaves room at the side, the yardage from every tee sits next to it.
struct MapPane: View {
    let course: Course
    let tee: String
    @Binding var selectedHole: Int

    @State private var drawingArea: CGSize = .zero
    /// While the drawing is zoomed in, it takes the yardages' room too.
    @State private var zoomed = false
    /// The narrowest the yardage list can be.
    private static let factsWidth: CGFloat = 132

    private var hole: Hole? { course.hole(selectedHole) }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Button {
                    selectedHole = max(selectedHole - 1, 1)
                } label: {
                    Image(systemName: "chevron.left").font(.title2)
                }
                .disabled(selectedHole <= 1)
                .accessibilityLabel("Previous hole")
                .accessibilityIdentifier("previous-hole")

                Spacer()
                VStack(spacing: 2) {
                    Text("Hole \(selectedHole)").font(.title2.bold())
                    if let hole {
                        Text(details(for: hole)).foregroundStyle(.secondary)
                    }
                }
                Spacer()

                Button {
                    selectedHole = min(selectedHole + 1, course.holes.count)
                } label: {
                    Image(systemName: "chevron.right").font(.title2)
                }
                .disabled(selectedHole >= course.holes.count)
                .accessibilityLabel("Next hole")
                .accessibilityIdentifier("next-hole")
            }
            .padding(.horizontal)

            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onGeometryChange(for: CGSize.self) { $0.size } action: { drawingArea = $0 }
                .overlay { drawingAndFacts }
                .padding(.horizontal)
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("map-pane")
    }

    /// The drawing, with the tee yardages beside it when there's room.
    private var drawingAndFacts: some View {
        let drawingWidth = min(drawingArea.width, drawingArea.height * HoleDrawing.aspect(of: hole))
        let spare = drawingArea.width - drawingWidth - 20
        let showFacts = hole?.map != nil && spare >= Self.factsWidth && !zoomed
        return HStack(spacing: showFacts ? 20 : 0) {
            ZoomableHoleDrawing(hole: hole, isZoomed: $zoomed)
                .frame(width: showFacts ? drawingWidth : drawingArea.width)
            if showFacts, let hole {
                TeeYardages(course: course, hole: hole, playedTee: tee)
                    .frame(width: min(spare, 220), alignment: .leading)
            }
        }
        .animation(.spring(duration: 0.3), value: zoomed)
    }

    private func details(for hole: Hole) -> String {
        var parts = ["Par \(hole.par)"]
        if let yards = hole.yards[tee] { parts.append("\(yards) yds") }
        if let handicap = course.handicap(hole: hole.number, tee: tee) { parts.append("Hcp \(handicap)") }
        return parts.joined(separator: " · ")
    }
}

/// The drawing for a hole, or a simple placeholder until it's drawn.
///
/// Downloaded courses bring their drawings as SVG files (see `HoleSketch`);
/// built-in courses have theirs in the asset catalog. A downloaded drawing
/// wins, since it's the newer copy.
struct HoleDrawing: View {
    let hole: Hole?

    /// Width over height of a hole's drawing.
    static func aspect(of hole: Hole?) -> CGFloat {
        guard let name = hole?.map else { return 0.5 }
        if let sketch = HoleSketches.shared.sketch(named: name) { return CGFloat(sketch.aspect) }
        guard let size = UIImage(named: name)?.size, size.height > 0 else { return 0.5 }
        return size.width / size.height
    }

    var body: some View {
        if let name = hole?.map, let sketch = HoleSketches.shared.sketch(named: name) {
            HoleSketchView(sketch: sketch)
                .accessibilityElement()
                .accessibilityAddTraits(.isImage)
                .accessibilityLabel("Map of hole \(hole?.number ?? 0)")
        } else if let name = hole?.map, UIImage(named: name) != nil {
            // Drawn from the vector asset, so it stays sharp when zoomed.
            Image(name)
                .resizable()
                .scaledToFit()
                .accessibilityLabel("Map of hole \(hole?.number ?? 0)")
        } else {
            HolePlaceholder()
        }
    }
}

/// Draws a downloaded hole drawing. It's redrawn at whatever size it's shown,
/// so it stays sharp when zoomed, like the built-in vector drawings.
struct HoleSketchView: View {
    let sketch: HoleSketch

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width / sketch.width, size.height / sketch.height)
            context.translateBy(
                x: (size.width - sketch.width * scale) / 2 - sketch.minX * scale,
                y: (size.height - sketch.height * scale) / 2 - sketch.minY * scale
            )
            context.scaleBy(x: scale, y: scale)
            for element in sketch.elements {
                var layer = context
                layer.opacity = element.opacity
                let path = Self.path(for: element.shape)
                if let fill = element.fill {
                    layer.fill(path, with: .color(Self.color(fill)))
                }
                if let stroke = element.stroke {
                    layer.stroke(path, with: .color(Self.color(stroke)), style: StrokeStyle(
                        lineWidth: element.strokeWidth,
                        lineCap: element.lineCap == "round" ? .round : element.lineCap == "square" ? .square : .butt,
                        lineJoin: element.lineJoin == "round" ? .round : element.lineJoin == "bevel" ? .bevel : .miter
                    ))
                }
            }
        }
        .aspectRatio(CGFloat(sketch.aspect), contentMode: .fit)
    }

    private static func color(_ rgb: HoleSketch.RGB) -> Color {
        Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    private static func path(for shape: HoleSketch.Shape) -> Path {
        func point(_ p: HoleSketch.Point) -> CGPoint { CGPoint(x: p.x, y: p.y) }
        var path = Path()
        switch shape {
        case .circle(let center, let radius):
            path.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        case .path(let segments):
            for segment in segments {
                switch segment {
                case .move(let p): path.move(to: point(p))
                case .line(let p): path.addLine(to: point(p))
                case .curve(let c1, let c2, let end): path.addCurve(to: point(end), control1: point(c1), control2: point(c2))
                case .close: path.closeSubpath()
                }
            }
        }
        return path
    }
}

/// A hole drawing you can pinch to zoom in and out, drag around while zoomed,
/// and double tap to zoom in or back out. It zooms back out for the next hole.
struct ZoomableHoleDrawing: View {
    let hole: Hole?
    @Binding var isZoomed: Bool

    @State private var scale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @GestureState private var pinch: CGFloat = 1
    @GestureState private var pinchAnchor: UnitPoint = .center
    @GestureState private var drag: CGSize = .zero

    private static let maxScale: CGFloat = 5
    private static let doubleTapScale: CGFloat = 2.5

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let current = min(Self.maxScale, max(1, scale * pinch))
            let shift = clamped(zoomed(offset, from: scale, to: current, at: pinchAnchor, in: size) + drag, scale: current, in: size)
            HoleDrawing(hole: hole)
                .accessibilityValue(scale > 1 ? "Zoomed in" : "Zoomed out")
                .frame(width: size.width * current, height: size.height * current)
                .offset(shift)
                .frame(width: size.width, height: size.height)
                .contentShape(Rectangle())
                .gesture(magnify(in: size).simultaneously(with: pan(in: size)))
                .onTapGesture(count: 2) {
                    withAnimation(.spring(duration: 0.3)) {
                        if scale > 1 { reset() } else { scale = Self.doubleTapScale }
                    }
                }
        }
        .clipped()
        .onChange(of: hole?.number) { reset() }
        .onChange(of: scale) { _, newScale in isZoomed = newScale > 1 }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("hole-drawing")
        .accessibilityZoomAction { action in
            withAnimation {
                switch action.direction {
                case .zoomIn: scale = min(Self.maxScale, scale * 1.5)
                case .zoomOut: scale = max(1, scale / 1.5)
                }
                if scale == 1 { offset = .zero }
            }
        }
    }

    private func reset() {
        scale = 1
        offset = .zero
    }

    private func magnify(in size: CGSize) -> some Gesture {
        MagnifyGesture()
            .updating($pinch) { value, state, _ in state = value.magnification }
            .updating($pinchAnchor) { value, state, _ in state = value.startAnchor }
            .onEnded { value in
                let newScale = min(Self.maxScale, max(1, scale * value.magnification))
                offset = clamped(zoomed(offset, from: scale, to: newScale, at: value.startAnchor, in: size), scale: newScale, in: size)
                scale = newScale
            }
    }

    private func pan(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .updating($drag) { value, state, _ in state = value.translation }
            .onEnded { value in
                offset = clamped(offset + value.translation, scale: scale, in: size)
            }
    }

    /// The offset that keeps the spot between the fingers under the fingers
    /// while the zoom changes.
    private func zoomed(_ offset: CGSize, from oldScale: CGFloat, to newScale: CGFloat, at anchor: UnitPoint, in size: CGSize) -> CGSize {
        let point = CGSize(width: (anchor.x - 0.5) * size.width, height: (anchor.y - 0.5) * size.height)
        let factor = newScale / oldScale
        return CGSize(
            width: point.width - (point.width - offset.width) * factor,
            height: point.height - (point.height - offset.height) * factor
        )
    }

    /// Keeps the zoomed drawing covering the frame, so it can't be dragged away.
    private func clamped(_ offset: CGSize, scale: CGFloat, in size: CGSize) -> CGSize {
        let maxX = size.width * (scale - 1) / 2
        let maxY = size.height * (scale - 1) / 2
        return CGSize(width: min(maxX, max(-maxX, offset.width)), height: min(maxY, max(-maxY, offset.height)))
    }
}

private func + (lhs: CGSize, rhs: CGSize) -> CGSize {
    CGSize(width: lhs.width + rhs.width, height: lhs.height + rhs.height)
}

struct HolePlaceholder: View {
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color.green.opacity(0.08))
                Capsule()
                    .fill(Color.green.opacity(0.25))
                    .frame(width: min(width * 0.35, 120), height: height * 0.7)
                Circle()
                    .fill(Color.green.opacity(0.45))
                    .frame(width: min(width * 0.3, 90), height: min(width * 0.3, 90))
                    .offset(y: -height * 0.33)
                Text("Hole drawing coming soon")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .offset(y: height * 0.42)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Hole drawing coming soon")
    }
}

/// How long the hole plays from each tee, in the tee colors of the card.
struct TeeYardages: View {
    let course: Course
    let hole: Hole
    let playedTee: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Yards").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(course.tees, id: \.self) { tee in
                if let yards = hole.yards[tee] {
                    let style = TeeStyle.row(for: tee)
                    let played = tee == playedTee
                    HStack(spacing: 10) {
                        Text("\(yards)")
                            .font(.title3.monospacedDigit().weight(played ? .bold : .medium))
                            .foregroundStyle(style.ink)
                            .frame(minWidth: 64)
                            .padding(.vertical, 6)
                            .background(style.band, in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(CardColors.line, lineWidth: 0.5))
                        Text(tee)
                            .font(.subheadline.weight(played ? .bold : .regular))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(tee) tees, \(yards) yards\(played ? ", playing" : "")")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tee-yardages")
    }
}
