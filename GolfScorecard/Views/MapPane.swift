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
    @ViewBuilder
    private var drawingAndFacts: some View {
        let drawingWidth = min(drawingArea.width, drawingArea.height * HoleDrawing.aspect(of: hole))
        let spare = drawingArea.width - drawingWidth - 20
        if let hole, hole.map != nil, spare >= Self.factsWidth {
            HStack(spacing: 20) {
                HoleDrawing(hole: hole)
                    .frame(width: drawingWidth)
                TeeYardages(course: course, hole: hole, playedTee: tee)
                    .frame(width: min(spare, 220), alignment: .leading)
            }
        } else {
            HoleDrawing(hole: hole)
        }
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
        if let name = hole?.map, let image = UIImage(named: name) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .accessibilityLabel("Map of hole \(hole?.number ?? 0)")
        } else {
            HolePlaceholder()
        }
    }
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
