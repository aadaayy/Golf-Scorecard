import Foundation

/// A hole drawing read the way a yardage book draws it: which shapes are
/// rough, fairway, water, sand, the green and the tees, where the pin is, the
/// line of play from the back tee, and a ring of trees around the edge.
///
/// The parts are told apart by the colors `Tools/HoleDrawings/trace_holes.py`
/// gives them, so built-in and downloaded courses work alike. A shape in any
/// other color is kept as it is. Like `HoleSketch`, it only uses Foundation,
/// so the logic tests can check every hole on any computer.
struct HolePlan {
    typealias Point = HoleSketch.Point

    enum Kind: Equatable {
        case water, rough, fairway, sand, green, tee
        /// The dashed line from the back tee to the green.
        case playLine
        /// A dot on the line of play where a shot lands.
        case landing
        case flagpole, flag, pin
        /// Anything else, drawn in its own colors.
        case other
    }

    struct Part {
        var kind: Kind
        var element: HoleSketch.Element
        /// The shape as straight lines, curves flattened.
        var outline: [Point]
    }

    struct Tree: Equatable {
        var center: Point
        var radius: Double
    }

    let parts: [Part]
    let trees: [Tree]
    /// Where the flag stands.
    let pin: Point?
    /// The middle of the green, which the yardage arcs measure to.
    let greenCenter: Point?
    /// From the back tee to the green.
    let playLine: [Point]
    /// The drawing's box, grown to fit the trees.
    let minX: Double
    let minY: Double
    let width: Double
    let height: Double

    var aspect: Double { height > 0 ? width / height : 0.5 }

    /// The green's outline, if the drawing has one.
    var green: Part? { parts.first { $0.kind == .green } }

    init(sketch: HoleSketch) {
        var parts = sketch.elements.map { element in
            Part(kind: Self.kind(of: element), element: element, outline: Self.outline(of: element.shape))
        }

        // The line of play is the first open dark line; a short upright one is the flagpole.
        var playLine: [Point] = []
        for index in parts.indices where parts[index].kind == .playLine {
            let points = parts[index].outline
            if points.count == 2, abs(points[0].x - points[1].x) < 0.5, Self.length(points) < 80 {
                parts[index].kind = .flagpole
            } else if playLine.isEmpty {
                playLine = points
            } else {
                parts[index].kind = .other
            }
        }

        // The pin: the small white dot with no edge, or the foot of the flagpole.
        var pin = parts.first { $0.kind == .pin }.flatMap { Self.center(of: $0.element.shape) }
        if pin == nil, let pole = parts.first(where: { $0.kind == .flagpole }) {
            pin = pole.outline.max { $0.y < $1.y }
        }

        // Greens and tees share a color: the green holds the pin (or ends the
        // line of play), and the rest are tees.
        let greenish = parts.indices.filter { parts[$0].kind == .green }
        var greenIndex: Int?
        if let target = pin ?? playLine.last {
            greenIndex = greenish.first { Self.contains(parts[$0].outline, target) }
                ?? greenish.min { Self.distance(Self.centroid(parts[$0].outline), target) < Self.distance(Self.centroid(parts[$1].outline), target) }
        } else {
            greenIndex = greenish.min { Self.centroid(parts[$0].outline).y < Self.centroid(parts[$1].outline).y }
        }
        for index in greenish where index != greenIndex {
            parts[index].kind = .tee
        }
        if let greenIndex, greenIndex != greenish.first {
            // Keep the green first among the green shapes, so `green` finds it.
            parts.swapAt(greenIndex, greenish[0])
        }

        self.parts = parts
        self.pin = pin
        self.playLine = playLine
        let greenOutline = parts.first { $0.kind == .green }?.outline
        self.greenCenter = greenOutline.map(Self.centroid)

        // Trees around the outside of the hole, about one every tree width.
        let size = max(sketch.width, sketch.height)
        let radius = size * 0.0105
        let trees = Self.plantTrees(around: parts, radius: radius)
        self.trees = trees

        var box = (minX: sketch.minX, minY: sketch.minY, maxX: sketch.minX + sketch.width, maxY: sketch.minY + sketch.height)
        for tree in trees {
            let reach = tree.radius * 1.3
            box.minX = min(box.minX, tree.center.x - reach)
            box.minY = min(box.minY, tree.center.y - reach)
            box.maxX = max(box.maxX, tree.center.x + reach)
            box.maxY = max(box.maxY, tree.center.y + reach)
        }
        minX = box.minX
        minY = box.minY
        width = box.maxX - box.minX
        height = box.maxY - box.minY
    }

    // MARK: Yards

    /// Drawing units per yard. The line of play runs from the back tee, so its
    /// length (to the middle of the green) is the hole's longest yardage.
    func unitsPerYard(backTeeYards: Int) -> Double? {
        guard backTeeYards > 0, playLine.count >= 2 else { return nil }
        var length = Self.length(playLine)
        if let greenCenter, let last = playLine.last {
            length += Self.distance(last, greenCenter)
        }
        return length > 0 ? length / Double(backTeeYards) : nil
    }

    /// The yardage arcs to draw: every 50 yards from 100 out to 300, as long
    /// as the arc is shorter than the hole.
    func arcYards(backTeeYards: Int) -> [Int] {
        guard let perYard = unitsPerYard(backTeeYards: backTeeYards),
              let greenCenter, let start = playLine.first else { return [] }
        let reach = Self.distance(start, greenCenter) / perYard
        return stride(from: 100, through: 300, by: 50).filter { Double($0) < reach - 15 }
    }

    /// Where the arc `radius` from the middle of the green crosses the line
    /// of play, coming back from the green. That's where its label goes.
    func crossing(radius: Double) -> Point? {
        guard let center = greenCenter, playLine.count >= 2 else { return nil }
        var points = playLine
        if let last = points.last, Self.distance(last, center) > 0.5 { points.append(center) }
        // Walk from the green back toward the tee.
        for index in stride(from: points.count - 1, to: 0, by: -1) {
            let a = points[index], b = points[index - 1]
            let da = Self.distance(a, center), db = Self.distance(b, center)
            guard (da - radius) * (db - radius) <= 0 else { continue }
            // Solve |a + t(b - a) - center| = radius for t in 0...1.
            let dx = b.x - a.x, dy = b.y - a.y
            let fx = a.x - center.x, fy = a.y - center.y
            let qa = dx * dx + dy * dy
            guard qa > 0 else { continue }
            let qb = 2 * (fx * dx + fy * dy)
            let qc = fx * fx + fy * fy - radius * radius
            let disc = max(0, qb * qb - 4 * qa * qc)
            let roots = [(-qb + disc.squareRoot()) / (2 * qa), (-qb - disc.squareRoot()) / (2 * qa)]
            if let t = roots.filter({ $0 >= -0.0001 && $0 <= 1.0001 }).min() {
                return Point(x: a.x + t * dx, y: a.y + t * dy)
            }
        }
        return nil
    }

    /// How deep the green is, front to back along the way you play into it, in yards.
    func greenDepth(backTeeYards: Int) -> Int? {
        guard let outline = green?.outline, outline.count > 2,
              let perYard = unitsPerYard(backTeeYards: backTeeYards),
              let center = greenCenter else { return nil }
        // The direction of the last shot into the green.
        var from = playLine.count >= 2 ? playLine[playLine.count - 2] : Point(x: center.x, y: center.y + 1)
        if let last = playLine.last, Self.distance(last, center) > 1 { from = last }
        let dx = center.x - from.x, dy = center.y - from.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 0 else { return nil }
        let projections = outline.map { ($0.x * dx + $0.y * dy) / length }
        guard let low = projections.min(), let high = projections.max() else { return nil }
        return Int(((high - low) / perYard).rounded())
    }

    /// The farthest the green reaches from its middle.
    var greenRadius: Double {
        guard let center = greenCenter, let outline = green?.outline else { return 0 }
        return outline.map { Self.distance($0, center) }.max() ?? 0
    }

    // MARK: Telling the parts apart

    private static func kind(of element: HoleSketch.Element) -> Kind {
        if let fill = element.fill {
            if matches(fill, 0xA9CEEC) { return .water }
            if matches(fill, 0xDCE8C4) { return .rough }
            if matches(fill, 0x9FCC80) { return .fairway }
            if matches(fill, 0xF0DDA6) { return .sand }
            if matches(fill, 0x3E9A56) { return .green }
            if matches(fill, 0xD8433B) { return .flag }
            if matches(fill, 0xFFFFFF), case .circle = element.shape {
                return element.stroke == nil ? .pin : .landing
            }
            return .other
        }
        if let stroke = element.stroke, matches(stroke, 0x1F3A2B), case .path = element.shape {
            return .playLine
        }
        return .other
    }

    private static func matches(_ color: HoleSketch.RGB, _ hex: Int) -> Bool {
        let red = Double((hex >> 16) & 0xFF) / 255
        let green = Double((hex >> 8) & 0xFF) / 255
        let blue = Double(hex & 0xFF) / 255
        return abs(color.red - red) < 0.03 && abs(color.green - green) < 0.03 && abs(color.blue - blue) < 0.03
    }

    // MARK: Geometry

    static func outline(of shape: HoleSketch.Shape) -> [Point] {
        switch shape {
        case .circle(let center, let radius):
            return (0..<16).map { step in
                let angle = Double(step) / 16 * 2 * Double.pi
                return Point(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
            }
        case .path(let segments):
            var points: [Point] = []
            var current = Point(x: 0, y: 0)
            for segment in segments {
                switch segment {
                case .move(let p), .line(let p):
                    points.append(p)
                    current = p
                case .curve(let c1, let c2, let end):
                    for step in 1...6 {
                        let t = Double(step) / 6
                        let u = 1 - t
                        let x = u * u * u * current.x + 3 * u * u * t * c1.x + 3 * u * t * t * c2.x + t * t * t * end.x
                        let y = u * u * u * current.y + 3 * u * u * t * c1.y + 3 * u * t * t * c2.y + t * t * t * end.y
                        points.append(Point(x: x, y: y))
                    }
                    current = end
                case .close:
                    break
                }
            }
            return points
        }
    }

    private static func center(of shape: HoleSketch.Shape) -> Point? {
        if case .circle(let center, _) = shape { return center }
        return nil
    }

    static func distance(_ a: Point, _ b: Point) -> Double {
        ((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)).squareRoot()
    }

    static func length(_ points: [Point]) -> Double {
        zip(points, points.dropFirst()).reduce(0) { $0 + distance($1.0, $1.1) }
    }

    /// The middle of a closed outline (by area, falling back to the average point).
    static func centroid(_ points: [Point]) -> Point {
        guard points.count > 2 else {
            let n = Double(max(points.count, 1))
            return Point(x: points.reduce(0) { $0 + $1.x } / n, y: points.reduce(0) { $0 + $1.y } / n)
        }
        var area = 0.0, cx = 0.0, cy = 0.0
        for index in points.indices {
            let a = points[index], b = points[(index + 1) % points.count]
            let cross = a.x * b.y - b.x * a.y
            area += cross
            cx += (a.x + b.x) * cross
            cy += (a.y + b.y) * cross
        }
        if abs(area) < 1e-6 {
            let n = Double(points.count)
            return Point(x: points.reduce(0) { $0 + $1.x } / n, y: points.reduce(0) { $0 + $1.y } / n)
        }
        return Point(x: cx / (3 * area), y: cy / (3 * area))
    }

    /// Whether a point is inside a closed outline.
    static func contains(_ polygon: [Point], _ point: Point) -> Bool {
        guard polygon.count > 2 else { return false }
        var inside = false
        var j = polygon.count - 1
        for i in polygon.indices {
            let a = polygon[i], b = polygon[j]
            if (a.y > point.y) != (b.y > point.y),
               point.x < (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x {
                inside.toggle()
            }
            j = i
        }
        return inside
    }

    /// A row of trees just outside the rough and the water, never on the course.
    private static func plantTrees(around parts: [Part], radius: Double) -> [Tree] {
        let edges = parts.filter { ($0.kind == .rough || $0.kind == .water) && $0.outline.count > 2 }
        let ground = parts.filter { [Kind.rough, .water, .fairway, .green, .tee, .sand].contains($0.kind) && $0.outline.count > 2 }
        guard radius > 0 else { return [] }
        var trees: [Tree] = []
        let spacing = radius * 2.1
        for edge in edges {
            var points = edge.outline
            if let first = points.first { points.append(first) }
            var carried = 0.0
            for (a, b) in zip(points, points.dropFirst()) {
                let dx = b.x - a.x, dy = b.y - a.y
                let segment = (dx * dx + dy * dy).squareRoot()
                guard segment > 0 else { continue }
                var along = spacing - carried
                while along <= segment {
                    let t = along / segment
                    let spot = Point(x: a.x + dx * t, y: a.y + dy * t)
                    // Step out from the edge, on whichever side is outside the rough.
                    var normal = Point(x: -dy / segment, y: dx / segment)
                    let probe = Point(x: spot.x + normal.x * radius, y: spot.y + normal.y * radius)
                    if contains(edge.outline, probe) { normal = Point(x: -normal.x, y: -normal.y) }
                    let center = Point(x: spot.x + normal.x * radius * 1.25, y: spot.y + normal.y * radius * 1.25)
                    let clear = !ground.contains { contains($0.outline, center) }
                        && !trees.contains { distance($0.center, center) < radius * 1.7 }
                    if clear {
                        // A little variety in size, the same every time.
                        let wobble = 0.85 + 0.3 * abs(sin(center.x * 0.37 + center.y * 0.11))
                        trees.append(Tree(center: center, radius: radius * wobble))
                    }
                    along += spacing
                }
                carried = segment - (along - spacing)
            }
        }
        return trees
    }
}
