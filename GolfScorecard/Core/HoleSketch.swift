import Foundation

/// A hole drawing read from an SVG file, for courses downloaded from the
/// course library. Courses built into the app use the asset catalog instead.
///
/// It reads the plain SVG that `Tools/HoleDrawings/trace_holes.py` writes:
/// `path` (move, line, curve and close commands), `polyline`, `line` and
/// `circle`, each with a fill, a stroke, a stroke width and an opacity. Like
/// `Course`, it only uses Foundation, so the logic tests can check every
/// drawing on any computer.
struct HoleSketch: Equatable {
    struct Point: Equatable {
        var x: Double
        var y: Double
    }

    enum Segment: Equatable {
        case move(Point)
        case line(Point)
        case curve(Point, Point, to: Point)
        case close
    }

    enum Shape: Equatable {
        case path([Segment])
        case circle(center: Point, radius: Double)
    }

    struct RGB: Equatable {
        var red: Double
        var green: Double
        var blue: Double
    }

    struct Element: Equatable {
        var shape: Shape
        var fill: RGB?
        var stroke: RGB?
        var strokeWidth: Double = 1
        var opacity: Double = 1
        /// "butt", "round" or "square", as written in the file.
        var lineCap = "butt"
        /// "miter", "round" or "bevel", as written in the file.
        var lineJoin = "miter"
    }

    /// The part of the drawing's own coordinates that shows (the SVG viewBox).
    var minX: Double
    var minY: Double
    var width: Double
    var height: Double
    var elements: [Element]

    /// Width over height.
    var aspect: Double { height > 0 ? width / height : 0.5 }

    enum ParseError: Error, Equatable, CustomStringConvertible {
        case notSVG
        case noSize
        case badNumber(String)
        case unsupportedCommand(Character)
        case badColor(String)
        case empty

        var description: String {
            switch self {
            case .notSVG: return "not an SVG file"
            case .noSize: return "the drawing has no viewBox or size"
            case .badNumber(let text): return "can't read the number in \"\(text)\""
            case .unsupportedCommand(let command): return "uses the path command \(command), which the app doesn't draw"
            case .badColor(let text): return "can't read the color \(text)"
            case .empty: return "the drawing has nothing in it"
            }
        }
    }

    static func parse(_ data: Data) throws -> HoleSketch {
        guard let text = String(data: data, encoding: .utf8) else { throw ParseError.notSVG }
        return try parse(text)
    }

    static func parse(_ text: String) throws -> HoleSketch {
        let tags = Self.tags(in: text)
        guard let svg = tags.first(where: { $0.name == "svg" }) else { throw ParseError.notSVG }

        var box: [Double] = []
        if let viewBox = svg.attributes["viewBox"] {
            box = try numbers(in: viewBox)
        }
        if box.count != 4 {
            guard let width = svg.attributes["width"].flatMap(length), let height = svg.attributes["height"].flatMap(length) else {
                throw ParseError.noSize
            }
            box = [0, 0, width, height]
        }
        guard box[2] > 0, box[3] > 0 else { throw ParseError.noSize }

        var elements: [Element] = []
        for tag in tags {
            let shape: Shape
            switch tag.name {
            case "path":
                shape = .path(try segments(in: tag.attributes["d"] ?? ""))
            case "polyline", "polygon":
                let values = try numbers(in: tag.attributes["points"] ?? "")
                var segments: [Segment] = []
                var index = 0
                while index + 1 < values.count {
                    let point = Point(x: values[index], y: values[index + 1])
                    segments.append(segments.isEmpty ? .move(point) : .line(point))
                    index += 2
                }
                if tag.name == "polygon", !segments.isEmpty { segments.append(.close) }
                shape = .path(segments)
            case "line":
                let value = { (name: String) in Double(tag.attributes[name] ?? "0") ?? 0 }
                shape = .path([.move(Point(x: value("x1"), y: value("y1"))), .line(Point(x: value("x2"), y: value("y2")))])
            case "circle":
                let value = { (name: String) in Double(tag.attributes[name] ?? "0") ?? 0 }
                shape = .circle(center: Point(x: value("cx"), y: value("cy")), radius: value("r"))
            default:
                continue
            }

            // SVG fills shapes black unless told otherwise; a line has nothing to fill.
            var element = Element(shape: shape)
            element.fill = tag.name == "line" ? nil : try color(tag.attributes["fill"] ?? "#000000")
            element.stroke = try tag.attributes["stroke"].flatMap(color)
            element.strokeWidth = tag.attributes["stroke-width"].flatMap(length) ?? 1
            element.opacity = tag.attributes["opacity"].flatMap { Double($0) } ?? 1
            element.lineCap = tag.attributes["stroke-linecap"] ?? "butt"
            element.lineJoin = tag.attributes["stroke-linejoin"] ?? "miter"
            elements.append(element)
        }
        guard !elements.isEmpty else { throw ParseError.empty }
        return HoleSketch(minX: box[0], minY: box[1], width: box[2], height: box[3], elements: elements)
    }

    // MARK: - Reading the file

    private struct Tag {
        var name: String
        var attributes: [String: String]
    }

    /// Every opening tag in the file, with its attributes. Closing tags,
    /// comments and the XML header are skipped.
    private static func tags(in text: String) -> [Tag] {
        var tags: [Tag] = []
        var rest = Substring(text)
        while let open = rest.firstIndex(of: "<") {
            rest = rest[rest.index(after: open)...]
            guard let close = rest.firstIndex(of: ">") else { break }
            let inside = rest[..<close]
            rest = rest[rest.index(after: close)...]
            guard let first = inside.first, first.isLetter else { continue }

            let nameEnd = inside.firstIndex { $0.isWhitespace || $0 == "/" } ?? inside.endIndex
            var tag = Tag(name: String(inside[..<nameEnd]), attributes: [:])
            var attributes = inside[nameEnd...]
            // name="value" or name='value', one after another
            while let equals = attributes.firstIndex(of: "=") {
                let name = attributes[..<equals].trimmingCharacters(in: .whitespacesAndNewlines)
                var afterEquals = attributes[attributes.index(after: equals)...].drop { $0.isWhitespace }
                guard let quote = afterEquals.first, quote == "\"" || quote == "'" else { break }
                afterEquals = afterEquals.dropFirst()
                guard let end = afterEquals.firstIndex(of: quote) else { break }
                tag.attributes[name] = String(afterEquals[..<end])
                attributes = afterEquals[afterEquals.index(after: end)...]
            }
            tags.append(tag)
        }
        return tags
    }

    /// The numbers in a list like "30 -54 444 1704" or "111.0,1593.0 261.0,861.0".
    static func numbers(in text: String) throws -> [Double] {
        var scanner = NumberScanner(text)
        var values: [Double] = []
        while let value = try scanner.nextNumber() { values.append(value) }
        return values
    }

    /// A length like "296" or "296px".
    private static func length(_ text: String) -> Double? {
        Double(text.hasSuffix("px") ? String(text.dropLast(2)) : text)
    }

    /// "#3E9A56", "#fff" or "none".
    static func color(_ text: String) throws -> RGB? {
        let value = text.trimmingCharacters(in: .whitespaces).lowercased()
        if value == "none" || value == "transparent" { return nil }
        if value == "black" { return RGB(red: 0, green: 0, blue: 0) }
        if value == "white" { return RGB(red: 1, green: 1, blue: 1) }
        guard value.hasPrefix("#") else { throw ParseError.badColor(text) }
        var hex = String(value.dropFirst())
        if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
        guard hex.count == 6, let number = Int(hex, radix: 16) else { throw ParseError.badColor(text) }
        return RGB(
            red: Double((number >> 16) & 0xFF) / 255,
            green: Double((number >> 8) & 0xFF) / 255,
            blue: Double(number & 0xFF) / 255
        )
    }

    /// The segments of a path's "d", with relative commands turned into absolute points.
    static func segments(in data: String) throws -> [Segment] {
        var scanner = NumberScanner(data)
        var segments: [Segment] = []
        var current = Point(x: 0, y: 0)
        var start = current
        var command: Character?

        func point(relative: Bool) throws -> Point {
            guard let x = try scanner.nextNumber(), let y = try scanner.nextNumber() else {
                throw ParseError.badNumber(data)
            }
            return relative ? Point(x: current.x + x, y: current.y + y) : Point(x: x, y: y)
        }

        while true {
            if let next = scanner.nextCommand() {
                command = next
            } else if !scanner.hasNumber {
                break
            }
            guard let active = command else { throw ParseError.badNumber(data) }
            let relative = active.isLowercase
            switch active {
            case "M", "m":
                current = try point(relative: relative)
                start = current
                segments.append(.move(current))
                // More points after a move are lines.
                command = relative ? "l" : "L"
            case "L", "l":
                current = try point(relative: relative)
                segments.append(.line(current))
            case "H", "h":
                guard let x = try scanner.nextNumber() else { throw ParseError.badNumber(data) }
                current = Point(x: relative ? current.x + x : x, y: current.y)
                segments.append(.line(current))
            case "V", "v":
                guard let y = try scanner.nextNumber() else { throw ParseError.badNumber(data) }
                current = Point(x: current.x, y: relative ? current.y + y : y)
                segments.append(.line(current))
            case "C", "c":
                let first = try point(relative: relative)
                let second = try point(relative: relative)
                let end = try point(relative: relative)
                segments.append(.curve(first, second, to: end))
                current = end
            case "Z", "z":
                segments.append(.close)
                current = start
                command = nil
            default:
                throw ParseError.unsupportedCommand(active)
            }
        }
        return segments
    }
}

/// Reads path commands and numbers from SVG text, where numbers can be split
/// by spaces, commas or just a minus sign ("1.5-2").
private struct NumberScanner {
    private let characters: [Character]
    private var index = 0

    init(_ text: String) {
        characters = Array(text)
    }

    private mutating func skipSeparators() {
        while index < characters.count, characters[index].isWhitespace || characters[index] == "," {
            index += 1
        }
    }

    var hasNumber: Bool {
        var copy = self
        copy.skipSeparators()
        guard copy.index < copy.characters.count else { return false }
        let character = copy.characters[copy.index]
        return character.isNumber || character == "-" || character == "+" || character == "."
    }

    /// The next path command letter, if the next thing is one.
    mutating func nextCommand() -> Character? {
        skipSeparators()
        guard index < characters.count else { return nil }
        let character = characters[index]
        guard character.isLetter, character != "e", character != "E" else { return nil }
        index += 1
        return character
    }

    /// The next number, or nil when the next thing isn't one.
    mutating func nextNumber() throws -> Double? {
        guard hasNumber else { return nil }
        skipSeparators()
        let begin = index
        if characters[index] == "-" || characters[index] == "+" { index += 1 }
        var seenDot = false
        var seenExponent = false
        while index < characters.count {
            let character = characters[index]
            if character.isNumber {
                index += 1
            } else if character == ".", !seenDot, !seenExponent {
                seenDot = true
                index += 1
            } else if (character == "e" || character == "E"), !seenExponent {
                seenExponent = true
                index += 1
                if index < characters.count, characters[index] == "-" || characters[index] == "+" { index += 1 }
            } else {
                break
            }
        }
        let text = String(characters[begin..<index])
        guard let value = Double(text) else { throw HoleSketch.ParseError.badNumber(text) }
        return value
    }
}
