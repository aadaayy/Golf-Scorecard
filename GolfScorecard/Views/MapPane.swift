import SwiftUI
import UIKit

/// The hole you're on, drawn like a page of a yardage book: HOLE 3 and its
/// par at the top, the hole with red arcs for the yards to the middle of the
/// green, and under it (or beside it, when there's room at the side) a close
/// look at the green and the yards from every tee.
struct MapPane: View {
    let course: Course
    let tee: String
    @Binding var selectedHole: Int

    @State private var drawingArea: CGSize = .zero
    /// While the drawing is zoomed in, it takes the green's and the yardages' room too.
    @State private var zoomed = false
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    /// The narrowest the green and yardages can be beside the drawing.
    private static let sideWidth: CGFloat = 170
    /// The least height worth keeping for the drawing when the facts go under it.
    private static let minDrawingHeight: CGFloat = 260

    private var hole: Hole? { course.hole(selectedHole) }
    private var plan: HolePlan? { hole?.map.flatMap { HoleSketches.shared.plan(named: $0) } }
    private var backTeeYards: Int { hole?.yards.values.max() ?? 0 }
    private var compact: Bool { verticalSizeClass == .compact }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 8)
            Rectangle()
                .fill(Book.ink)
                .frame(height: 1)
                .padding(.horizontal)
                .padding(.top, compact ? 4 : 8)

            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onGeometryChange(for: CGSize.self) { $0.size } action: { drawingArea = $0 }
                .overlay { drawingAndFacts }
                .padding(.horizontal)
                .padding(.top, compact ? 6 : 12)
        }
        .padding(.vertical, compact ? 6 : 10)
        .paperBackground()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("map-pane")
    }

    /// HOLE 3 on the left, PAR 3 and the yards and stroke index on the right,
    /// with previous and next at the ends.
    private var header: some View {
        HStack(spacing: 6) {
            Button {
                selectedHole = max(selectedHole - 1, 1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title3.weight(.semibold))
                    .frame(width: 36, height: 44)
            }
            .disabled(selectedHole <= 1)
            .accessibilityLabel("Previous hole")
            .accessibilityIdentifier("previous-hole")

            Text("HOLE \(selectedHole)")
                .font(Book.title(compact ? 26 : 34, relativeTo: .largeTitle))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .accessibilityLabel("Hole \(selectedHole)")
            Spacer(minLength: 4)
            if let hole {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("PAR \(hole.par)")
                        .font(Book.title(compact ? 18 : 22))
                        .foregroundStyle(Book.red)
                        .accessibilityLabel("Par \(hole.par)")
                    Text(details(for: hole))
                        .font(Book.mono(12))
                        .foregroundStyle(Book.pencil)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            }

            Button {
                selectedHole = min(selectedHole + 1, course.holes.count)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.title3.weight(.semibold))
                    .frame(width: 36, height: 44)
            }
            .disabled(selectedHole >= course.holes.count)
            .accessibilityLabel("Next hole")
            .accessibilityIdentifier("next-hole")
        }
        .foregroundStyle(Book.ink)
    }

    /// The drawing, with the green and the tee yardages beside it or under it
    /// when there's room for them.
    @ViewBuilder
    private var drawingAndFacts: some View {
        let aspect = HoleDrawing.aspect(of: hole)
        let sideRoom = drawingArea.width - drawingArea.height * aspect - 20
        let hasFacts = hole?.map != nil && !zoomed
        let underHeight = factsHeight(side: false)
        Group {
            if hasFacts, sideRoom >= Self.sideWidth {
                // The hole keeps at least half the width, so it stays big enough to read and pinch.
                let factsWidth = min(sideRoom, 250, max(Self.sideWidth, (drawingArea.width - 20) / 2))
                HStack(spacing: 20) {
                    ZoomableHoleDrawing(hole: hole, isZoomed: $zoomed)
                        .frame(width: drawingArea.width - factsWidth - 20)
                    facts(side: true)
                        .frame(width: factsWidth)
                }
            } else if hasFacts, drawingArea.height - underHeight >= Self.minDrawingHeight {
                VStack(spacing: 10) {
                    ZoomableHoleDrawing(hole: hole, isZoomed: $zoomed)
                    Rectangle().fill(Book.rule).frame(height: 1)
                    facts(side: false)
                        .frame(height: underHeight - 11)
                }
            } else {
                ZoomableHoleDrawing(hole: hole, isZoomed: $zoomed)
            }
        }
        .animation(.spring(duration: 0.3), value: zoomed)
    }

    private var teeCount: Int { hole.map { h in course.tees.filter { h.yards[$0] != nil }.count } ?? 0 }
    private var tableHeight: CGFloat { 22 + CGFloat(teeCount) * 24 }
    private var hasArcs: Bool { !(plan?.arcYards(backTeeYards: backTeeYards).isEmpty ?? true) }

    /// Height the facts need under the drawing: the green (or the table, if taller) and the note about the arcs.
    private func factsHeight(side: Bool) -> CGFloat {
        max(tableHeight, 132) + (hasArcs ? 22 : 0) + 11
    }

    /// The close look at the green, the tee yardages and the note about the arcs.
    @ViewBuilder
    private func facts(side: Bool) -> some View {
        if side {
            let greenRoom = drawingArea.height - tableHeight - (hasArcs ? 40 : 18) - 30
            VStack(alignment: .leading, spacing: 10) {
                if let plan, greenRoom >= 80 {
                    GreenCloseUp(plan: plan, backTeeYards: backTeeYards)
                        .frame(width: min(greenRoom, 140, Self.sideWidth), height: min(greenRoom, 140, Self.sideWidth) + 18)
                        .frame(maxWidth: .infinity)
                }
                TeeYardages(course: course, hole: hole!, playedTee: tee)
                if hasArcs { arcNote }
            }
            .frame(maxHeight: .infinity)
        } else {
            VStack(spacing: 6) {
                HStack(alignment: .center, spacing: 16) {
                    if let plan {
                        GreenCloseUp(plan: plan, backTeeYards: backTeeYards)
                            .frame(width: 118, height: 132)
                    }
                    TeeYardages(course: course, hole: hole!, playedTee: tee)
                }
                if hasArcs { arcNote }
            }
        }
    }

    private var arcNote: some View {
        Text("Arcs show yards to the middle of the green")
            .font(Book.mono(10))
            .foregroundStyle(Book.pencil)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
    }

    private func details(for hole: Hole) -> String {
        var parts: [String] = []
        if let yards = hole.yards[tee] { parts.append("\(yards) yds") }
        if let handicap = course.handicap(hole: hole.number, tee: tee) { parts.append("hcp \(handicap)") }
        return parts.joined(separator: " · ")
    }
}

/// How much of a hole a drawing shows: the whole yardage book page, or a
/// plain one for small tiles like the nine view's.
enum HoleDetail {
    case full, simple
}

/// The drawing for a hole, or a simple placeholder until it's drawn.
///
/// Built-in courses keep their drawings in the asset catalog and downloaded
/// courses bring theirs as SVG files (see `HoleSketch`); both are read into a
/// `HolePlan` and drawn in the yardage book style.
struct HoleDrawing: View {
    let hole: Hole?
    var detail = HoleDetail.full

    /// Width over height of a hole's drawing.
    static func aspect(of hole: Hole?) -> CGFloat {
        guard let name = hole?.map else { return 0.5 }
        if let plan = HoleSketches.shared.plan(named: name) { return CGFloat(plan.aspect) }
        guard let size = UIImage(named: name)?.size, size.height > 0 else { return 0.5 }
        return size.width / size.height
    }

    var body: some View {
        if let hole, let name = hole.map, let plan = HoleSketches.shared.plan(named: name) {
            YardageHoleView(plan: plan, backTeeYards: hole.yards.values.max() ?? 0, detail: detail)
                .accessibilityElement()
                .accessibilityAddTraits(.isImage)
                .accessibilityLabel("Map of hole \(hole.number)")
        } else if let name = hole?.map, UIImage(named: name) != nil {
            Image(name)
                .resizable()
                .scaledToFit()
                .accessibilityLabel("Map of hole \(hole?.number ?? 0)")
        } else {
            HolePlaceholder()
        }
    }
}

/// A hole drawn like a yardage book page: pale rough inside a dashed edge,
/// water with ripples, ink outlines, trees around the outside, the line of
/// play, and red arcs every 50 yards to the middle of the green. It's redrawn
/// at whatever size it's shown, so it stays sharp when zoomed.
struct YardageHoleView: View {
    let plan: HolePlan
    /// The hole's longest yardage, which sets the scale of the arcs.
    let backTeeYards: Int
    var detail = HoleDetail.full

    var body: some View {
        Canvas { context, size in
            guard plan.width > 0, plan.height > 0 else { return }
            let scale = min(size.width / plan.width, size.height / plan.height)
            let pen = HolePen(
                scale: scale,
                origin: CGPoint(
                    x: (size.width - plan.width * scale) / 2 - plan.minX * scale,
                    y: (size.height - plan.height * scale) / 2 - plan.minY * scale
                )
            )
            let full = detail == .full
            pen.drawGround(plan, in: &context, hairline: full ? 0.8 : 0.5, waves: full || size.height > 160)
            pen.drawTrees(plan, in: &context, outlined: full)
            if full { drawYardage(in: &context, pen: pen, size: size) }
            pen.drawFlag(plan, in: &context, full: full)
        }
        .aspectRatio(CGFloat(plan.aspect), contentMode: .fit)
    }

    /// The red arcs, the line of play and the arcs' labels.
    private func drawYardage(in context: inout GraphicsContext, pen: HolePen, size: CGSize) {
        guard let perYard = plan.unitsPerYard(backTeeYards: backTeeYards), let center = plan.greenCenter else { return }
        let arcs = plan.arcYards(backTeeYards: backTeeYards)
        let clips = plan.parts.filter { ($0.kind == .rough || $0.kind == .water) && $0.outline.count > 2 }
        let middle = pen.point(center)
        for yards in arcs {
            let radius = Double(yards) * perYard * pen.scale
            let circle = Path(ellipseIn: CGRect(x: middle.x - radius, y: middle.y - radius, width: radius * 2, height: radius * 2))
            if clips.isEmpty {
                context.stroke(circle, with: .color(Book.red), lineWidth: 0.9)
            }
            // Only inside the hole: once for each piece of it, so water
            // outside the rough gets its arcs too.
            for part in clips {
                var clipped = context
                clipped.clip(to: pen.path(part.element.shape))
                clipped.stroke(circle, with: .color(Book.red), lineWidth: 0.9)
            }
        }

        // The line of play, dashed, from the back tee to the pin.
        var line = Path()
        for (index, point) in plan.playLine.enumerated() {
            if index == 0 { line.move(to: pen.point(point)) } else { line.addLine(to: pen.point(point)) }
        }
        if let pin = plan.pin ?? plan.greenCenter, !plan.playLine.isEmpty { line.addLine(to: pen.point(pin)) }
        context.stroke(line, with: .color(Book.ink.opacity(0.75)), style: StrokeStyle(lineWidth: 0.9, lineCap: .round, dash: [4, 3]))
        for part in plan.parts where part.kind == .landing {
            if case .circle(let spot, _) = part.element.shape {
                let p = pen.point(spot)
                let dot = Path(ellipseIn: CGRect(x: p.x - 2.6, y: p.y - 2.6, width: 5.2, height: 5.2))
                context.fill(dot, with: .color(Book.paper))
                context.stroke(dot, with: .color(Book.ink), lineWidth: 0.8)
            }
        }

        // Labels where each arc crosses the line, if they have room.
        guard size.height > 200 else { return }
        var placed: [CGPoint] = []
        for yards in arcs {
            guard let crossing = plan.crossing(radius: Double(yards) * perYard) else { continue }
            let at = pen.point(crossing)
            guard !placed.contains(where: { abs($0.y - at.y) < 16 && abs($0.x - at.x) < 34 }) else { continue }
            placed.append(at)
            let label = context.resolve(Text("\(yards)").font(Book.mono(10, weight: .bold)).foregroundStyle(Book.red))
            let measured = label.measure(in: CGSize(width: 80, height: 30))
            let box = CGRect(x: at.x - measured.width / 2 - 3.5, y: at.y - measured.height / 2 - 1.5,
                             width: measured.width + 7, height: measured.height + 3)
            let tag = Path(roundedRect: box, cornerRadius: 3)
            context.fill(tag, with: .color(Book.page))
            context.stroke(tag, with: .color(Book.red), lineWidth: 0.9)
            context.draw(label, at: at, anchor: .center)
        }
    }
}

/// Draws a hole plan's parts onto a canvas at a given scale and position.
struct HolePen {
    let scale: CGFloat
    /// Where the drawing's (0, 0) lands on the canvas.
    let origin: CGPoint

    func point(_ p: HoleSketch.Point) -> CGPoint {
        CGPoint(x: p.x * scale + origin.x, y: p.y * scale + origin.y)
    }

    func path(_ shape: HoleSketch.Shape) -> Path {
        var path = Path()
        switch shape {
        case .circle(let center, let radius):
            let c = point(center)
            let r = radius * scale
            path.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
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

    /// Rough, water, fairways, bunkers, tees and the green, in that order.
    func drawGround(_ plan: HolePlan, in context: inout GraphicsContext, hairline: CGFloat, waves: Bool, dashedEdge: Bool = true) {
        let order: [HolePlan.Kind] = [.rough, .water, .fairway, .sand, .tee, .green, .other]
        for kind in order {
            for part in plan.parts where part.kind == kind {
                let shape = path(part.element.shape)
                switch kind {
                case .rough:
                    context.fill(shape, with: .color(Book.rough))
                    if dashedEdge {
                        context.stroke(shape, with: .color(Book.ink.opacity(0.8)), style: StrokeStyle(lineWidth: hairline, dash: [3, 2.5]))
                    }
                case .water:
                    context.fill(shape, with: .color(Book.water))
                    if waves { drawWaves(in: shape, context: &context) }
                    context.stroke(shape, with: .color(Book.ink), lineWidth: hairline)
                case .fairway, .tee:
                    context.fill(shape, with: .color(Book.fairway))
                    context.stroke(shape, with: .color(Book.ink), lineWidth: hairline)
                case .sand:
                    context.fill(shape, with: .color(Book.sand))
                    context.stroke(shape, with: .color(Book.ink), lineWidth: hairline * 0.9)
                case .green:
                    context.fill(shape, with: .color(Book.green))
                    context.stroke(shape, with: .color(Book.ink), lineWidth: hairline * 1.6)
                default:
                    // Something this style doesn't know: drawn in its own colors.
                    var layer = context
                    layer.opacity = part.element.opacity
                    if let fill = part.element.fill {
                        layer.fill(shape, with: .color(Color(red: fill.red, green: fill.green, blue: fill.blue)))
                    }
                    if let stroke = part.element.stroke {
                        layer.stroke(shape, with: .color(Color(red: stroke.red, green: stroke.green, blue: stroke.blue)), lineWidth: part.element.strokeWidth * scale)
                    }
                }
            }
        }
    }

    /// Little ripples across a pond, like a pen sketch.
    private func drawWaves(in shape: Path, context: inout GraphicsContext) {
        let box = shape.boundingRect
        guard box.width > 4, box.height > 4 else { return }
        var ripples = context
        ripples.clip(to: shape)
        // Keep the count of ripples sensible when zoomed far in.
        let gap = max(6, box.height / 140)
        let step = max(8, box.width / 160)
        var waves = Path()
        var y = box.minY + gap / 2
        var row = 0
        while y < box.maxY {
            var x = box.minX - (row.isMultiple(of: 2) ? 0 : step / 2)
            waves.move(to: CGPoint(x: x, y: y))
            while x < box.maxX {
                waves.addQuadCurve(to: CGPoint(x: x + step / 2, y: y), control: CGPoint(x: x + step / 4, y: y - 1.3))
                waves.addQuadCurve(to: CGPoint(x: x + step, y: y), control: CGPoint(x: x + step * 0.75, y: y + 1.3))
                x += step
            }
            y += gap
            row += 1
        }
        ripples.stroke(waves, with: .color(Book.waterLine.opacity(0.75)), lineWidth: 0.6)
    }

    func drawTrees(_ plan: HolePlan, in context: inout GraphicsContext, outlined: Bool) {
        for tree in plan.trees {
            let c = point(tree.center)
            let r = tree.radius * scale
            let crown = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            context.fill(crown, with: .color(Book.tree))
            if outlined {
                context.stroke(crown, with: .color(Book.ink.opacity(0.85)), lineWidth: 0.7)
                if r > 4 {
                    context.fill(Path(ellipseIn: CGRect(x: c.x - 0.9, y: c.y - 0.9, width: 1.8, height: 1.8)), with: .color(Book.ink.opacity(0.7)))
                }
            } else {
                context.stroke(crown, with: .color(Book.ink.opacity(0.35)), lineWidth: 0.4)
            }
        }
    }

    /// The flagpole, the red flag and the hole.
    func drawFlag(_ plan: HolePlan, in context: inout GraphicsContext, full: Bool) {
        for part in plan.parts {
            switch part.kind {
            case .flagpole:
                context.stroke(path(part.element.shape), with: .color(Book.ink), style: StrokeStyle(lineWidth: full ? 1.2 : 0.8, lineCap: .round))
            case .flag:
                context.fill(path(part.element.shape), with: .color(Book.red))
            case .pin:
                if let pin = plan.pin {
                    let p = point(pin)
                    let r: CGFloat = full ? 1.8 : 1.2
                    context.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .color(Book.ink))
                }
            default:
                break
            }
        }
    }
}

/// A close look at the green in a circle, with the bunkers and water around
/// it, and how deep the green is.
struct GreenCloseUp: View {
    let plan: HolePlan
    let backTeeYards: Int

    var body: some View {
        VStack(spacing: 4) {
            Canvas { context, size in
                guard let center = plan.greenCenter, plan.greenRadius > 0 else { return }
                let side = min(size.width, size.height) - 2
                let scale = side / 2 / (plan.greenRadius * 1.9)
                let middle = CGPoint(x: size.width / 2, y: size.height / 2)
                let pen = HolePen(scale: scale, origin: CGPoint(x: middle.x - center.x * scale, y: middle.y - center.y * scale))
                let ring = Path(ellipseIn: CGRect(x: middle.x - side / 2, y: middle.y - side / 2, width: side, height: side))
                var inside = context
                inside.clip(to: ring)
                inside.fill(ring, with: .color(Book.rough))
                pen.drawGround(plan, in: &inside, hairline: 1, waves: true, dashedEdge: false)
                pen.drawFlag(plan, in: &inside, full: true)
                context.stroke(ring, with: .color(Book.ink), lineWidth: 1.3)
            }
            .aspectRatio(1, contentMode: .fit)
            Text(caption)
                .font(Book.mono(10, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(depth.map { "The green, \($0) yards deep" } ?? "The green")
    }

    private var depth: Int? { plan.greenDepth(backTeeYards: backTeeYards) }

    private var caption: String {
        depth.map { "GREEN · \($0) DEEP" } ?? "GREEN"
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
                    .fill(Book.page)
                    .overlay(RoundedRectangle(cornerRadius: 24).stroke(Book.rule, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                Capsule()
                    .fill(Book.fairway)
                    .overlay(Capsule().stroke(Book.ink, lineWidth: 0.8))
                    .frame(width: min(width * 0.35, 120), height: height * 0.7)
                Circle()
                    .fill(Book.green)
                    .overlay(Circle().stroke(Book.ink, lineWidth: 1.2))
                    .frame(width: min(width * 0.3, 90), height: min(width * 0.3, 90))
                    .offset(y: -height * 0.33)
                Text("Hole drawing coming soon")
                    .font(.footnote)
                    .foregroundStyle(Book.pencil)
                    .offset(y: height * 0.42)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Hole drawing coming soon")
    }
}

/// How long the hole plays from each tee, like the table at the foot of a
/// yardage book page: the tee's color, its name, dots, and the yards. The
/// tee being played is in bold, its yards in red.
struct TeeYardages: View {
    let course: Course
    let hole: Hole
    let playedTee: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("TEE")
                Spacer()
                Text("YARDS")
            }
            .font(Book.mono(11, weight: .bold))
            .accessibilityHidden(true)
            ForEach(course.tees, id: \.self) { tee in
                if let yards = hole.yards[tee] {
                    let played = tee == playedTee
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(TeeStyle.row(for: tee).band)
                            .overlay(RoundedRectangle(cornerRadius: 2).stroke(Book.ink.opacity(0.7), lineWidth: 0.8))
                            .frame(width: 12, height: 12)
                        Text(tee)
                            .font(Book.mono(15, weight: played ? .bold : .regular))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .layoutPriority(1)
                        DottedLeader()
                        Text("\(yards)")
                            .font(Book.mono(15, weight: played ? .bold : .medium))
                            .foregroundStyle(played ? Book.red : Book.ink)
                            .layoutPriority(1)
                    }
                    .frame(height: 18)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(tee) tees, \(yards) yards\(played ? ", playing" : "")")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tee-yardages")
    }
}

/// The row of dots between a tee's name and its yards.
struct DottedLeader: View {
    var body: some View {
        GeometryReader { geometry in
            Path { path in
                let y = geometry.size.height - 4
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: geometry.size.width, y: y))
            }
            .stroke(Book.ink.opacity(0.5), style: StrokeStyle(lineWidth: 1.1, lineCap: .round, dash: [0.1, 4]))
        }
        .frame(minWidth: 6, maxHeight: 18)
        .accessibilityHidden(true)
    }
}
