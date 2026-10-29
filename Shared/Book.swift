import SwiftUI

/// The Yardage Book look: ink on cream paper with red marks, like the little
/// book a caddie keeps in a back pocket. Shared by the app and its Lock
/// Screen card.
enum Book {
    // Paper and ink
    /// The page everything sits on.
    static let paper = Color(red: 0.961, green: 0.937, blue: 0.871)
    /// A lighter sheet for rows, boxes and cards on the page.
    static let page = Color(red: 0.988, green: 0.976, blue: 0.937)
    /// A darker shade of paper, for bands and switches.
    static let shade = Color(red: 0.914, green: 0.882, blue: 0.796)
    static let ink = Color(red: 0.149, green: 0.180, blue: 0.204)
    /// Softer ink for second lines and notes. Still easy to read on the paper.
    static let pencil = Color(red: 0.400, green: 0.365, blue: 0.306)
    /// The red of yardage marks, the flag and the hole's par.
    static let red = Color(red: 0.690, green: 0.282, blue: 0.204)
    /// Thin rules between rows.
    static let rule = ink.opacity(0.22)
    /// The row, hole or tile you've picked.
    static let marked = red.opacity(0.13)

    // The hole drawings
    static let rough = Color(red: 0.918, green: 0.925, blue: 0.839)
    static let fairway = Color(red: 0.824, green: 0.886, blue: 0.714)
    static let green = Color(red: 0.729, green: 0.839, blue: 0.643)
    static let water = Color(red: 0.769, green: 0.855, blue: 0.910)
    static let waterLine = Color(red: 0.506, green: 0.647, blue: 0.749)
    static let sand = Color(red: 0.925, green: 0.871, blue: 0.729)
    static let tree = Color(red: 0.776, green: 0.863, blue: 0.690)
    /// Darker green, for text and ticks that mean "on your phone".
    static let leaf = Color(red: 0.204, green: 0.400, blue: 0.220)

    // Type: a typewriter face for titles, plain monospaced type for the rest.
    private static let typewriterBoldName = "CourierNewPS-BoldMT"
    private static let typewriterName = "CourierNewPSMT"

    /// Big typewriter titles, like HOLE 3 at the top of a page.
    static func title(_ size: CGFloat, relativeTo style: Font.TextStyle = .title) -> Font {
        .custom(typewriterBoldName, size: size, relativeTo: style)
    }

    /// Typewriter text in a regular weight.
    static func type(_ size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom(typewriterName, size: size, relativeTo: style)
    }

    /// Typewriter type at a fixed size, for the score card's row names.
    static func typewriter(_ size: CGFloat, bold: Bool) -> Font {
        .custom(bold ? typewriterBoldName : typewriterName, fixedSize: size)
    }

    /// Monospaced figures and labels at a fixed size.
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

/// The paper the app is printed on: cream with a faint grid, like the pages
/// of a yardage book.
struct PaperBackground: View {
    var color = Book.paper

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(color))
            let step: CGFloat = 22
            var grid = Path()
            var x: CGFloat = step
            while x < size.width {
                grid.move(to: CGPoint(x: x, y: 0))
                grid.addLine(to: CGPoint(x: x, y: size.height))
                x += step
            }
            var y: CGFloat = step
            while y < size.height {
                grid.move(to: CGPoint(x: 0, y: y))
                grid.addLine(to: CGPoint(x: size.width, y: y))
                y += step
            }
            context.stroke(grid, with: .color(Book.ink.opacity(0.045)), lineWidth: 0.5)
        }
        .accessibilityHidden(true)
    }
}

extension View {
    /// Paper behind the whole screen, under the bars too.
    func paperBackground() -> some View {
        background { PaperBackground().ignoresSafeArea() }
    }

    /// A box on the page: a lighter sheet with an ink edge.
    func bookBox(cornerRadius: CGFloat = 12, fill: Color = Book.page) -> some View {
        background(fill, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(Book.ink.opacity(0.55), lineWidth: 1))
    }
}
