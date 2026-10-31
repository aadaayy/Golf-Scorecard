import SwiftUI
import SwiftData

/// Before a round: the tee and who's playing. You're already the first player,
/// and people you've played with before are a tap away.
struct NewRoundView: View {
    let course: Course
    var onStart: (Round) -> Void

    @Environment(\.modelContext) private var modelContext
    @AppStorage(SettingsKey.playerName) private var playerName = ""
    @AppStorage(SettingsKey.handicap) private var handicap = ""
    @AppStorage(SettingsKey.usualTee) private var usualTee = "White"
    @Query(sort: \Round.date, order: .reverse) private var pastRounds: [Round]
    @State private var tee = ""
    @State private var players: [String] = []
    @Environment(GroupSession.self) private var group
    @State private var showingSignIn = false
    @State private var showingNotSetUp = false
    @State private var startingGroup = false
    @State private var groupProblem: String?

    private let maxPlayers = 4

    var body: some View {
        Form {
            if course.tees.isEmpty {
                Section {
                    Text("Par \(course.par(holes: 1...course.holes.count)) · no tee yardages for this course yet")
                        .foregroundStyle(Book.pencil)
                        .bookRow()
                } header: {
                    Text("Tee")
                }
            } else {
                Section {
                    Picker("Tee", selection: $tee) {
                        ForEach(course.tees, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .bookRow()
                } header: {
                    Text("Tee")
                } footer: {
                    if !tee.isEmpty {
                        Text("\(tee) tees · \(course.yards(tee: tee, holes: 1...course.holes.count)) yards · Par \(course.par(holes: 1...course.holes.count))")
                    }
                }
            }

            Section {
                ForEach(0..<players.count, id: \.self) { index in
                    HStack {
                        TextField("Player \(index + 1)", text: name(at: index))
                            .textInputAutocapitalization(.words)
                            .accessibilityIdentifier("player-\(index)")
                        if index > 0 {
                            Button {
                                if players.indices.contains(index) { players.remove(at: index) }
                            } label: {
                                Image(systemName: "minus.circle.fill").foregroundStyle(Book.red)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove player \(index + 1)")
                        }
                    }
                    .bookRow()
                }
                if players.count < maxPlayers {
                    Button {
                        players.append("")
                    } label: {
                        Label("Add Player", systemImage: "plus.circle")
                    }
                    .bookRow()
                    .accessibilityIdentifier("add-player")
                }
            } header: {
                Text("Players")
            } footer: {
                if !suggestions.isEmpty && players.count < maxPlayers {
                    suggestionChips
                }
            }

            Section {
                Button(action: start) {
                    Label("Start Round", systemImage: "flag.fill")
                        .font(Book.title(19, relativeTo: .headline))
                        .foregroundStyle(Book.paper)
                        .frame(maxWidth: .infinity)
                }
                .listRowBackground(Book.ink)
                .accessibilityIdentifier("start-round")
            }

            Section {
                Button(action: startGroupTapped) {
                    HStack {
                        if startingGroup { ProgressView() }
                        Label(startingGroup ? "Starting…" : "Start Group Round", systemImage: "person.2.fill")
                            .font(Book.title(18, relativeTo: .headline))
                    }
                    .foregroundStyle(Book.ink)
                    .frame(maxWidth: .infinity)
                }
                .disabled(startingGroup)
                .bookRow()
                .accessibilityIdentifier("start-group-round")
            } footer: {
                if let groupProblem {
                    Text(groupProblem).foregroundStyle(Book.red).accessibilityIdentifier("group-problem")
                } else {
                    Text("Friends join from their own phones with a code. Everyone keeps their own score, and everyone's card fills in live.")
                }
            }
        }
        .bookList()
        .sheet(isPresented: $showingSignIn, onDismiss: {
            if group.user != nil { startGroup() }
        }) {
            GroupSignInSheet()
        }
        .alert("Group rounds aren't set up yet", isPresented: $showingNotSetUp) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This copy of the app isn't connected to its group-round database. The steps are under Group rounds setup in the README.")
        }
        .navigationTitle(course.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: fillIn)
    }

    /// People from past rounds who aren't on the card yet.
    private var suggestions: [String] {
        let onCard = players.filter { !$0.isEmpty } + [playerName, "Me"]
        return PlayerNames.recent(from: pastRounds.map { Array($0.players.dropFirst()) }, excluding: onCard)
    }

    private var suggestionChips: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Played with before").font(.footnote)
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(suggestions, id: \.self) { name in
                        Button {
                            add(name)
                        } label: {
                            Label(name, systemImage: "plus")
                                .font(.subheadline)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Book.page, in: Capsule())
                                .overlay(Capsule().stroke(Book.ink.opacity(0.5), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("suggested-\(name)")
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(.top, 6)
    }

    /// A name field's text. Checked against the list, since a removed row can
    /// still be asked for its text while it animates away.
    private func name(at index: Int) -> Binding<String> {
        Binding(
            get: { players.indices.contains(index) ? players[index] : "" },
            set: { if players.indices.contains(index) { players[index] = $0 } }
        )
    }

    /// Fills the first empty name, or adds a player.
    private func add(_ name: String) {
        if let empty = players.indices.dropFirst().first(where: { players[$0].trimmingCharacters(in: .whitespaces).isEmpty }) {
            players[empty] = name
        } else if players.count < maxPlayers {
            players.append(name)
        }
    }

    private func fillIn() {
        if players.isEmpty {
            players = [playerName.isEmpty ? "Me" : playerName]
        }
        // The usual tee if this course has it, then White, then the middle of the list.
        if tee.isEmpty {
            tee = [usualTee, "White"].first(where: { course.tees.contains($0) }) ?? course.tees[safe: course.tees.count / 2] ?? ""
        }
    }

    private func startGroupTapped() {
        groupProblem = nil
        if !group.isSetUp {
            showingNotSetUp = true
        } else if group.user == nil {
            showingSignIn = true
        } else {
            startGroup()
        }
    }

    /// A group round has just you on the card; friends add themselves.
    private func startGroup() {
        guard !startingGroup else { return }
        let name = players.first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        let me = name.isEmpty ? (playerName.isEmpty ? (group.user?.name ?? "Me") : playerName) : name
        startingGroup = true
        Task {
            defer { startingGroup = false }
            do {
                let round = try await group.startRound(course: course, tee: tee, playerName: me,
                                                       handicap: HandicapIndex.parse(handicap), in: modelContext)
                onStart(round)
            } catch {
                groupProblem = error.localizedDescription
            }
        }
    }

    private func start() {
        let names = players.enumerated().map { index, name in
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? "Player \(index + 1)" : trimmed
        }
        let round = Round(course: course, tee: tee, players: names, playerHandicap: HandicapIndex.parse(handicap))
        modelContext.insert(round)
        onStart(round)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
