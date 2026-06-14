import SwiftUI
import SwiftData

/// Open a new round: pick a matchday's fixtures (deselect any) and set the
/// picks deadline (spec §6.3).
struct OpenRoundView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let game: Game
    /// The kind of round to open. Tie follow-ups pass `.playoff`/`.rollover`.
    var roundType: RoundType = .normal
    /// Called after a round is successfully opened (e.g. to dismiss a parent).
    var onOpened: () -> Void = {}

    @State private var data: LeagueData?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var matchday = 1
    @State private var selectedFixtureIds: Set<Int> = []
    @State private var deadline = Date()

    private var matchdays: [Int] {
        Array(Set((data?.fixtures ?? []).compactMap(\.matchday))).sorted()
    }
    private var matchdayFixtures: [FixtureDTO] {
        (data?.fixtures ?? []).filter { $0.matchday == matchday }.sorted { $0.kickoff < $1.kickoff }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && data == nil {
                    ProgressView("Loading fixtures…")
                } else if let errorMessage, data == nil {
                    ContentUnavailableView("Couldn't load fixtures", systemImage: "wifi.slash", description: Text(errorMessage))
                } else {
                    form
                }
            }
            .navigationTitle("Open \(roundType.openTitle) \(GameLogicService.nextRoundNumber(for: game))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Open") { create() }.disabled(selectedFixtureIds.isEmpty)
                }
            }
            .task { await load() }
        }
    }

    private var form: some View {
        Form {
            Section {
                Picker("Matchday", selection: $matchday) {
                    ForEach(matchdays, id: \.self) { Text("Matchday \($0)").tag($0) }
                }
                .onChange(of: matchday) { selectAllInMatchday() }
            }
            Section("Fixtures (\(selectedFixtureIds.count) selected)") {
                ForEach(matchdayFixtures) { fixture in
                    Button {
                        toggle(fixture.id)
                    } label: {
                        HStack {
                            Image(systemName: selectedFixtureIds.contains(fixture.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selectedFixtureIds.contains(fixture.id) ? .green : .secondary)
                            FixtureLabel(fixture: fixture, teamsById: data?.teamsById ?? [:])
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            Section("Deadline") {
                DatePicker("Picks due by", selection: $deadline)
            }
        }
    }

    private func toggle(_ id: Int) {
        if selectedFixtureIds.contains(id) { selectedFixtureIds.remove(id) } else { selectedFixtureIds.insert(id) }
    }

    private func selectAllInMatchday() {
        selectedFixtureIds = Set(matchdayFixtures.map(\.id))
        if let first = matchdayFixtures.first, let date = FixtureFormat.kickoffDate(first.kickoff) {
            deadline = date
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            data = try await LeagueData.load()
            matchday = matchdays.first ?? 1
            selectAllInMatchday()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func create() {
        GameLogicService.openRound(
            in: game,
            fixtureIds: Array(selectedFixtureIds),
            deadline: deadline,
            roundType: roundType,
            context: context
        )
        onOpened()
        dismiss()
    }
}
