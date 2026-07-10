import SwiftUI

/// Lets a manager type in a one-off fixture by hand — e.g. a local pub team
/// dropping in for a laugh, or a stand-in if the real fixture provider is
/// unavailable — from inside round-opening. Shared by LMS and Predictor
/// (`OpenRoundView` is mode-agnostic). See `ManualFixtureService`.
struct AddManualFixtureSheet: View {
    @Environment(\.dismiss) private var dismiss
    let game: Game
    /// Names of every real (non-manual) team already loaded for this game's
    /// league(s) — checked against on submit so a manual name can't shadow one.
    let realTeamNames: Set<String>
    let existingManualTeams: [TeamDTO]
    let onAdd: (_ home: TeamDTO, _ away: TeamDTO, _ kickoff: Date) -> Void

    @State private var homeName = ""
    @State private var awayName = ""
    @State private var kickoff = Date()
    @State private var errorMessage: String?

    private var trimmedHome: String { homeName.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedAway: String { awayName.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var namesValid: Bool {
        !trimmedHome.isEmpty && !trimmedAway.isEmpty
            && trimmedHome.localizedCaseInsensitiveCompare(trimmedAway) != .orderedSame
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Home team", text: $homeName)
                        .textInputAutocapitalization(.words)
                    TextField("Away team", text: $awayName)
                        .textInputAutocapitalization(.words)
                    DatePicker("Kick-off", selection: $kickoff)
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("For a one-off game only — e.g. a local team dropping in for a laugh, or a stand-in if fixtures aren't available. Scores are entered by hand too.")
                        Text("Names are checked against this game's league(s); if a real team is ever added with the same name, this entry is replaced automatically.")
                    }
                }

                if !existingManualTeams.isEmpty {
                    Section("Already used in this game") {
                        ForEach(existingManualTeams) { team in
                            Text(team.name).foregroundStyle(.secondary)
                        }
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Add Manual Fixture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { add() }.disabled(!namesValid)
                }
            }
        }
    }

    private func add() {
        errorMessage = nil
        switch ManualFixtureService.team(named: trimmedHome, for: game, realTeamNames: realTeamNames) {
        case .failure(let error):
            errorMessage = error.errorDescription
        case .success(let home):
            switch ManualFixtureService.team(named: trimmedAway, for: game, realTeamNames: realTeamNames) {
            case .failure(let error):
                errorMessage = error.errorDescription
            case .success(let away):
                onAdd(home, away, kickoff)
                dismiss()
            }
        }
    }
}
