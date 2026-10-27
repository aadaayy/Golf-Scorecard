import SwiftUI
import SwiftData

struct PastRoundsView: View {
    @Query(sort: \Round.date, order: .reverse) private var rounds: [Round]
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        List {
            ForEach(rounds) { round in
                NavigationLink(value: round) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(round.courseName).font(.headline)
                            Text(round.date, format: .dateTime.month().day().year())
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(round.grid.total(player: 0, holes: 1...StrokeGrid.holeCount))")
                            .font(.title3.monospacedDigit())
                    }
                }
            }
            .onDelete { offsets in
                for index in offsets { modelContext.delete(rounds[index]) }
            }
        }
        .overlay {
            if rounds.isEmpty {
                ContentUnavailableView("No rounds yet", systemImage: "flag", description: Text("Rounds you start appear here."))
            }
        }
        .navigationTitle("Past Rounds")
    }
}
