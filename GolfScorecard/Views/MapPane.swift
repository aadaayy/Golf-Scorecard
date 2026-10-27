import SwiftUI
import UIKit

/// The hole map for the selected hole, with previous and next buttons.
struct MapPane: View {
    let course: Course
    let tee: String
    @Binding var selectedHole: Int

    private var hole: Hole? { course.hole(selectedHole) }

    var body: some View {
        VStack(spacing: 12) {
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

            HoleDrawing(hole: hole)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
        }
        .padding(.vertical)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("map-pane")
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
