import SwiftUI
import SwiftData

/// Every round on this phone, newest first. Swipe left to delete one.
///
/// Upright, a round opens on its card. Open on the Duo or sideways, the list
/// sits on the left and the picked round's totals on the right, with a button
/// to open its card. Finished cards stay locked until Edit.
struct PastRoundsView: View {
    @Query(sort: \Round.date, order: .reverse) private var rounds: [Round]
    @Environment(\.modelContext) private var modelContext
    @Environment(CourseLibrary.self) private var library
    @Environment(\.openRound) private var openRound
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var pickedID: PersistentIdentifier?

    private var isWide: Bool { horizontalSizeClass == .regular || verticalSizeClass == .compact }
    private var picked: Round? {
        rounds.first { $0.persistentModelID == pickedID } ?? rounds.first
    }

    var body: some View {
        Group {
            if isWide && !rounds.isEmpty {
                WideRoundLayout(card: list, map: detail)
            } else {
                list
            }
        }
        .overlay {
            if rounds.isEmpty {
                ContentUnavailableView("No rounds yet", systemImage: "flag", description: Text("Rounds you play show up here."))
            }
        }
        .navigationTitle("Past Rounds")
        .navigationBarTitleDisplayMode(isWide ? .inline : .large)
    }

    private var list: some View {
        List {
            ForEach(Array(rounds.enumerated()), id: \.element.persistentModelID) { index, round in
                Group {
                    if isWide {
                        Button {
                            pickedID = round.persistentModelID
                        } label: {
                            row(round).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .bookRow(marked: round.persistentModelID == picked?.persistentModelID)
                    } else {
                        Button {
                            openRound(round)
                        } label: {
                            HStack {
                                row(round)
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(Book.pencil)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .bookRow()
                    }
                }
                .accessibilityIdentifier("past-round-\(index)")
            }
            .onDelete { offsets in
                for index in offsets { modelContext.delete(rounds[index]) }
            }
        }
        .bookList()
    }

    /// The picked round's totals and a button to open its card.
    @ViewBuilder
    private var detail: some View {
        if let round = picked, let course = library.course(id: round.courseID) {
            ScrollView {
                VStack(spacing: 16) {
                    RoundTotals(round: round, course: course)
                    Button {
                        openRound(round)
                    } label: {
                        Label(round.isFinished ? "Open Card" : "Resume Round",
                              systemImage: round.isFinished ? "list.number" : "play.fill")
                            .font(.headline)
                            .frame(maxWidth: 360)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .foregroundStyle(Book.paper)
                    .accessibilityIdentifier("open-round")
                }
                .padding()
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .paperBackground()
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("round-detail")
        } else {
            ContentUnavailableView("Pick a round", systemImage: "clock.arrow.circlepath")
        }
    }

    private func row(_ round: Round) -> some View {
        let grid = round.grid
        let total = grid.total(player: round.me, holes: 1...StrokeGrid.holeCount)
        let played = grid.holesPlayed(player: round.me, holes: 1...StrokeGrid.holeCount)
        let toPar = library.course(id: round.courseID).flatMap { grid.toPar(player: round.me, course: $0) }
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(round.courseName).font(Book.title(18, relativeTo: .headline))
                Text(subtitle(round)).font(.subheadline).foregroundStyle(Book.pencil)
                if !round.isFinished {
                    Text(played == 0 ? "Not started" : "Unfinished · thru \(played)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Book.red)
                }
            }
            Spacer()
            if total > 0 {
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(total)").font(.title2.bold())
                    if let toPar {
                        Text(RoundSummaryView.toParText(toPar)).font(.caption).foregroundStyle(Book.pencil)
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
