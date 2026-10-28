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
struct HoleDrawing: View {
    let hole: Hole?

    /// Width over height of a hole's drawing.
    static func aspect(of hole: Hole?) -> CGFloat {
        guard let name = hole?.map, let size = UIImage(named: name)?.size, size.height > 0 else { return 0.5 }
        return size.width / size.height
    }

    var body: some View {
        if let name = hole?.map, UIImage(named: name) != nil {
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

/// A hole drawing you can pinch to zoom in and out, drag around while zoomed,
/// and double tap to zoom in or back out. It zooms back out for the next hole.
struct ZoomableHoleDrawing: View {
    let hole: Hole?
    @Binding var isZoomed: Bool

    @State private var scale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @GestureState private var pinch: CGFloat = 1
    @GestureState private var drag: CGSize = .zero

    private static let maxScale: CGFloat = 5
    private static let doubleTapScale: CGFloat = 2.5

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let current = min(Self.maxScale, max(1, scale * pinch))
            let shift = clamped(offset + drag, scale: current, in: size)
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
            .onEnded { value in
                scale = min(Self.maxScale, max(1, scale * value.magnification))
                offset = clamped(offset, scale: scale, in: size)
            }
    }

    private func pan(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .updating($drag) { value, state, _ in state = value.translation }
            .onEnded { value in
                offset = clamped(offset + value.translation, scale: scale, in: size)
            }
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
