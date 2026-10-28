import SwiftUI
import SwiftData

/// Every round on this phone, newest first. A round opens on its card; finished
/// ones stay locked until Edit. Swipe left to delete one.
struct PastRoundsView: View {
    @Query(sort: \Round.date, order: .reverse) private var rounds: [Round]
    @Environment(\.modelContext) private var modelContext
    @Environment(CourseLibrary.self) private var library

    var body: some View {
        List {
            ForEach(rounds) { round in
                NavigationLink(value: round) {
                    row(round)
                }
                .accessibilityIdentifier("past-round-\(rounds.firstIndex(of: round) ?? 0)")
            }
            .onDelete { offsets in
                for index in offsets { modelContext.delete(rounds[index]) }
            }
        }
        .overlay {
            if rounds.isEmpty {
                ContentUnavailableView("No rounds yet", systemImage: "flag", description: Text("Rounds you play show up here."))
            }
        }
        .navigationTitle("Past Rounds")
    }

    private func row(_ round: Round) -> some View {
        let grid = round.grid
        let total = grid.total(player: 0, holes: 1...StrokeGrid.holeCount)
        let played = grid.holesPlayed(player: 0, holes: 1...StrokeGrid.holeCount)
        let toPar = library.course(id: round.courseID).flatMap { grid.toPar(player: 0, course: $0) }
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(round.courseName).font(.headline)
                Text(subtitle(round)).font(.subheadline).foregroundStyle(.secondary)
                if !round.isFinished {
                    Text(played == 0 ? "Not started" : "Unfinished · thru \(played)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
            if total > 0 {
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(total)").font(.title2.bold().monospacedDigit())
                    if let toPar {
                        Text(RoundSummaryView.toParText(toPar)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    /// "Oct 27, 2026 · White · with Sam, Jo"
    private func subtitle(_ round: Round) -> String {
        var parts = [round.date.formatted(date: .abbreviated, time: .omitted), round.tee]
        let others = round.players.dropFirst()
        if !others.isEmpty { parts.append("with " + others.joined(separator: ", ")) }
        return parts.joined(separator: " · ")
    }
}
