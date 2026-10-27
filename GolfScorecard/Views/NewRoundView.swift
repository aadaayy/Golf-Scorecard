import SwiftUI
import SwiftData

struct NewRoundView: View {
    let course: Course
    var onStart: (Round) -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var tee = ""
    @State private var players = ["Me"]

    private let maxPlayers = 4

    var body: some View {
        Form {
            Section("Tee") {
                Picker("Tee", selection: $tee) {
                    ForEach(course.tees, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Section("Players") {
                ForEach(0..<players.count, id: \.self) { index in
                    TextField("Player \(index + 1)", text: $players[index])
                        .textInputAutocapitalization(.words)
                }
                if players.count < maxPlayers {
                    Button("Add Player") { players.append("") }
                }
                if players.count > 1 {
                    Button("Remove Last Player", role: .destructive) { players.removeLast() }
                }
            }

            Section {
                Button("Start Round", action: start)
                    .accessibilityIdentifier("start-round")
            }
        }
        .navigationTitle(course.name)
        .onAppear {
            if tee.isEmpty { tee = course.tees.first ?? "" }
        }
    }

    private func start() {
        let names = players.enumerated().map { index, name in
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? "Player \(index + 1)" : trimmed
        }
        let round = Round(course: course, tee: tee, players: names)
        modelContext.insert(round)
        onStart(round)
    }
}
