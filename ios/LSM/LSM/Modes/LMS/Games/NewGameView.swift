import SwiftUI
import SwiftData

/// Create-game form (spec §6.1). Anonymity is set once here and can't change
/// mid-season. Tie / all-eliminated outcomes are chosen in the moment when they
/// actually arise (see `TieResolutionView`), not pre-committed at creation.
struct NewGameView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(EnabledLeagues.self) private var enabled
    @AppStorage(ManagerSettings.nameKey) private var managerName = ""

    /// nil shows the mode picker; choosing a mode reveals its form.
    @State private var mode: GameMode?

    @State private var name = ""
    @State private var season = Leagues.app.season
    @State private var anonymity: AnonymityMode = .anonymous
    @State private var selectedLeagueIds: Set<String> = []
    @State private var managerPlaying = true   // manager opts in/out per game
    @State private var drawEliminates = true
    @State private var postponedEliminates = false

    // Predictor scoring config — prefilled from the manager's last-used
    // settings (§0 "implicit remember last settings", no named templates).
    @State private var predictorExactPoints = PredictorSettings.lastExactPoints
    @State private var predictorGDEnabled = PredictorSettings.lastGDEnabled
    @State private var predictorGDPoints = PredictorSettings.lastGDPoints
    @State private var predictorResultEnabled = PredictorSettings.lastResultEnabled
    @State private var predictorResultPoints = PredictorSettings.lastResultPoints
    @State private var predictorJokerEnabled = PredictorSettings.lastJokerEnabled

    // Killer settings — prefilled from the manager's last-used settings, same
    // "implicit remember last settings" pattern as Predictor.
    @State private var killerBuildPhaseRounds = KillerSettings.lastBuildPhaseRounds
    @State private var killerMaxAdditionalLives = KillerSettings.lastMaxAdditionalLives
    @State private var killerMaxMPG = KillerSettings.lastMaxMPG

    private var managerTrimmed: String { managerName.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canCreate: Bool { !trimmedName.isEmpty && !selectedLeagueIds.isEmpty && !wouldExceedLeagueAllowance }

    /// Leagues currently used by any non-completed game. These stay available
    /// for further games no matter what the current tier allows — a lapsed
    /// subscription never interrupts a game already in progress. Only picking
    /// a league beyond this set needs allowance headroom (see
    /// `wouldExceedLeagueAllowance`), mirroring how `maxActiveGames` only
    /// gates game creation, never existing games.
    private var activeLeagueIds: Set<String> {
        let completeRaw = GameStatus.complete.rawValue
        let descriptor = FetchDescriptor<Game>(predicate: #Predicate { $0.statusRaw != completeRaw })
        let games = (try? context.fetch(descriptor)) ?? []
        return Set(games.flatMap(\.leagueIdsRaw))
    }

    /// True only when the selection adds a league not already in active use
    /// AND doing so would push the total past the tier's allowance. Selecting
    /// exclusively from already-active leagues is always allowed, even if the
    /// manager is already over allowance from a downgrade.
    private var wouldExceedLeagueAllowance: Bool {
        let newSelections = selectedLeagueIds.subtracting(activeLeagueIds)
        guard !newSelections.isEmpty else { return false }
        return activeLeagueIds.union(selectedLeagueIds).count > Entitlements.shared.leagueAllowance
    }

    var body: some View {
        NavigationStack {
            Group {
                if let mode {
                    form(for: mode)
                } else {
                    modePicker
                }
            }
        }
    }

    private var modePicker: some View {
        Form {
            Section {
                ForEach(GameMode.allCases) { candidate in
                    Button { mode = candidate } label: {
                        HStack {
                            Text(candidate.displayName).foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.secondary)
                        }
                    }
                }
            } footer: {
                Text("Last Man Standing eliminates a player on a wrong pick. Predictor scores every player's predicted scoreline each round — no elimination.")
            }
        }
        .navigationTitle("New Game")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }

    @ViewBuilder
    private func form(for mode: GameMode) -> some View {
        switch mode {
        case .lms: lmsForm
        case .predictor: predictorForm
        case .killer: killerForm
        }
    }

    private var lmsForm: some View {
            Form {
                Section("Game") {
                    TextField("Game name", text: $name)
                }

                // Always shown so the manager can always see which league(s) a game
                // will use. A single-league setup shows that one league greyed out
                // (nothing to choose); 2+ leagues is an interactive, forced choice —
                // none pre-ticked, so a manager never silently blends leagues they
                // didn't mean to.
                Section {
                    ForEach(enabled.leagues) { league in
                        if enabled.leagues.count == 1 {
                            HStack {
                                Text(league.name).foregroundStyle(.secondary)
                                Spacer()
                                Image(systemName: "checkmark").foregroundStyle(.secondary)
                            }
                        } else {
                            Button {
                                toggleLeague(league.id)
                            } label: {
                                HStack {
                                    Text(league.name).foregroundStyle(.primary)
                                    Spacer()
                                    if selectedLeagueIds.contains(league.id) {
                                        Image(systemName: "checkmark").foregroundStyle(.tint)
                                    }
                                }
                            }
                        }
                    }
                } header: {
                    Text("Leagues")
                } footer: {
                    if wouldExceedLeagueAllowance {
                        Text("Your plan doesn't cover an extra league right now. Leagues already in use by another game stay available to pick from — upgrade to add a new one.")
                    } else {
                        Text(enabled.leagues.count == 1
                             ? "Your only enabled league. Enable more in Settings to blend leagues in a game."
                             : "Pick one league, or blend several — players can then pick teams from any of them.")
                    }
                }

                if !managerTrimmed.isEmpty {
                    Section {
                        Button {
                            managerPlaying.toggle()
                        } label: {
                            HStack {
                                Text("\(managerTrimmed) (you)").foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: managerPlaying ? "minus.circle.fill" : "plus.circle")
                                    .foregroundStyle(managerPlaying ? .red : .blue)
                            }
                        }
                    } header: {
                        Text("You")
                    } footer: {
                        Text(managerPlaying
                             ? "You're playing in this game — your pick shows on shared cards (⚑)."
                             : "You're running this game but not playing — no ⚑ on cards.")
                    }
                }

                Section {
                    HStack {
                        Text("Win").foregroundStyle(.secondary)
                        Spacer()
                        Text("Survives").foregroundStyle(.secondary)
                    }
                    Toggle(isOn: $postponedEliminates) {
                        resultRuleLabel("Postponed", eliminates: postponedEliminates)
                    }
                    Toggle(isOn: $drawEliminates) {
                        resultRuleLabel("Draw", eliminates: drawEliminates)
                    }
                    HStack {
                        Text("Loss").foregroundStyle(.secondary)
                        Spacer()
                        Text("Eliminates").foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Result Rules")
                } footer: {
                    // Single localized string key — can't wrap without changing the key.
                    // swiftlint:disable:next line_length
                    Text("A win always survives and a loss always eliminates. Toggle on for Postponed/Draw to treat them as a loss too — off keeps them as a survive.")
                }

                Section("Summaries") {
                    Picker("Anonymity", selection: $anonymity) {
                        ForEach(AnonymityMode.allCases) { Text($0.label).tag($0) }
                    }
                }
            }
            .navigationTitle("New Game")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { create() }
                        .disabled(!canCreate)
                }
            }
            // Single-league setup: zero-tap default (nothing to choose). 2+
            // leagues: no default tick at all — the manager must explicitly
            // choose, so a game is never created with a league they didn't mean
            // to include (see the Leagues section above).
            .onAppear {
                if selectedLeagueIds.isEmpty, enabled.leagues.count == 1 {
                    selectedLeagueIds = Set(enabled.leagues.map(\.id))
                }
            }
    }

    private func resultRuleLabel(_ title: LocalizedStringKey, eliminates: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).foregroundStyle(.primary)
            Text(eliminates ? "Counts as a loss" : "Counts as a win")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func toggleLeague(_ id: String) {
        if selectedLeagueIds.contains(id) { selectedLeagueIds.remove(id) } else { selectedLeagueIds.insert(id) }
    }

    private func create() {
        guard activeGameCount() < Entitlements.shared.maxActiveGames, !wouldExceedLeagueAllowance else { return }
        let game = Game(
            name: trimmedName,
            season: season,
            allowRepeats: Leagues.app.allowRepeatDefault,
            anonymityMode: anonymity,
            leagueIds: Array(selectedLeagueIds),
            drawEliminates: drawEliminates,
            postponedEliminates: postponedEliminates,
            mode: .lms
        )
        context.insert(game)
        addManagerIfPlaying(to: game)
        dismiss()
    }

    // MARK: - Predictor

    private var predictorForm: some View {
        Form {
            Section("Game") {
                TextField("Game name", text: $name)
            }

            Section {
                ForEach(enabled.leagues) { league in
                    if enabled.leagues.count == 1 {
                        HStack {
                            Text(league.name).foregroundStyle(.secondary)
                            Spacer()
                            Image(systemName: "checkmark").foregroundStyle(.secondary)
                        }
                    } else {
                        Button {
                            toggleLeague(league.id)
                        } label: {
                            HStack {
                                Text(league.name).foregroundStyle(.primary)
                                Spacer()
                                if selectedLeagueIds.contains(league.id) {
                                    Image(systemName: "checkmark").foregroundStyle(.tint)
                                }
                            }
                        }
                    }
                }
            } header: {
                Text("Leagues")
            } footer: {
                if wouldExceedLeagueAllowance {
                    Text("Your plan doesn't cover an extra league right now. Leagues already in use by another game stay available to pick from — upgrade to add a new one.")
                } else {
                    Text(enabled.leagues.count == 1
                         ? "Your only enabled league. Enable more in Settings to blend leagues in a game."
                         : "Pick one league, or blend several — predictions can then cover fixtures from any of them.")
                }
            }

            if !managerTrimmed.isEmpty {
                Section {
                    Button {
                        managerPlaying.toggle()
                    } label: {
                        HStack {
                            Text("\(managerTrimmed) (you)").foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: managerPlaying ? "minus.circle.fill" : "plus.circle")
                                .foregroundStyle(managerPlaying ? .red : .blue)
                        }
                    }
                } header: {
                    Text("You")
                } footer: {
                    Text(managerPlaying
                         ? "You're playing in this game — your predictions count toward the league table."
                         : "You're running this game but not playing.")
                }
            }

            Section {
                Stepper("Exact score: \(predictorExactPoints) pts", value: $predictorExactPoints, in: 1...10)
                Toggle(isOn: $predictorGDEnabled) {
                    Text("Goal difference")
                }
                if predictorGDEnabled {
                    Stepper("\(predictorGDPoints) pts", value: $predictorGDPoints, in: 1...10)
                }
                Toggle(isOn: $predictorResultEnabled) {
                    Text("Correct result")
                }
                if predictorResultEnabled {
                    Stepper("\(predictorResultPoints) pts", value: $predictorResultPoints, in: 1...10)
                }
                Toggle("Joker (double points, one fixture/round)", isOn: $predictorJokerEnabled)
            } header: {
                Text("Scoring")
            } footer: {
                Text("Each prediction earns the single highest rung it qualifies for. A correct non-exact draw lands on Goal difference, not Result.")
            }
        }
        .navigationTitle("New Game")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Create") { createPredictor() }
                    .disabled(!canCreate)
            }
        }
        .onAppear {
            if selectedLeagueIds.isEmpty, enabled.leagues.count == 1 {
                selectedLeagueIds = Set(enabled.leagues.map(\.id))
            }
        }
    }

    private func createPredictor() {
        guard activeGameCount() < Entitlements.shared.maxActiveGames, !wouldExceedLeagueAllowance else { return }
        let game = Game(
            name: trimmedName,
            season: season,
            allowRepeats: Leagues.app.allowRepeatDefault,
            leagueIds: Array(selectedLeagueIds),
            mode: .predictor,
            predictorExactPoints: predictorExactPoints,
            predictorGDEnabled: predictorGDEnabled,
            predictorGDPoints: predictorGDPoints,
            predictorResultEnabled: predictorResultEnabled,
            predictorResultPoints: predictorResultPoints,
            predictorJokerEnabled: predictorJokerEnabled
        )
        context.insert(game)
        addManagerIfPlaying(to: game)
        PredictorSettings.saveLastUsed(
            exactPoints: predictorExactPoints,
            gdEnabled: predictorGDEnabled,
            gdPoints: predictorGDPoints,
            resultEnabled: predictorResultEnabled,
            resultPoints: predictorResultPoints,
            jokerEnabled: predictorJokerEnabled
        )
        dismiss()
    }

    // MARK: - Killer

    private var killerForm: some View {
        Form {
            Section("Game") {
                TextField("Game name", text: $name)
            }

            Section {
                ForEach(enabled.leagues) { league in
                    if enabled.leagues.count == 1 {
                        HStack {
                            Text(league.name).foregroundStyle(.secondary)
                            Spacer()
                            Image(systemName: "checkmark").foregroundStyle(.secondary)
                        }
                    } else {
                        Button {
                            toggleLeague(league.id)
                        } label: {
                            HStack {
                                Text(league.name).foregroundStyle(.primary)
                                Spacer()
                                if selectedLeagueIds.contains(league.id) {
                                    Image(systemName: "checkmark").foregroundStyle(.tint)
                                }
                            }
                        }
                    }
                }
            } header: {
                Text("Leagues")
            } footer: {
                if wouldExceedLeagueAllowance {
                    Text("Your plan doesn't cover an extra league right now. Leagues already in use by another game stay available to pick from — upgrade to add a new one.")
                } else {
                    Text(enabled.leagues.count == 1
                         ? "Your only enabled league. Enable more in Settings to blend leagues in a game."
                         : "Pick one league, or blend several — Manager Picked Games can then come from any of them.")
                }
            }

            if !managerTrimmed.isEmpty {
                Section {
                    Button {
                        managerPlaying.toggle()
                    } label: {
                        HStack {
                            Text("\(managerTrimmed) (you)").foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: managerPlaying ? "minus.circle.fill" : "plus.circle")
                                .foregroundStyle(managerPlaying ? .red : .blue)
                        }
                    }
                } header: {
                    Text("You")
                } footer: {
                    Text(managerPlaying
                         ? "You're playing in this game — you have lives and can be eliminated."
                         : "You're running this game but not playing.")
                }
            }

            Section {
                Stepper("Build Phase: \(killerBuildPhaseRounds) round\(killerBuildPhaseRounds == 1 ? "" : "s")",
                        value: $killerBuildPhaseRounds, in: 1...10)
                Stepper("Max additional lives: \(killerMaxAdditionalLives)",
                        value: $killerMaxAdditionalLives, in: 0...20)
                Stepper("Max Manager Picked Games: \(killerMaxMPG)",
                        value: $killerMaxMPG, in: 1...10)
            } header: {
                Text("Killer Settings")
            } footer: {
                // swiftlint:disable:next line_length
                Text("Everyone starts with 1 life. During the Build Phase, a correct prediction earns +1 life (up to the cap). After that, the Kill Phase begins: predictions also fire a Hit at a chosen opponent.")
            }
        }
        .navigationTitle("New Game")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Create") { createKiller() }
                    .disabled(!canCreate)
            }
        }
        .onAppear {
            if selectedLeagueIds.isEmpty, enabled.leagues.count == 1 {
                selectedLeagueIds = Set(enabled.leagues.map(\.id))
            }
        }
    }

    private func createKiller() {
        guard activeGameCount() < Entitlements.shared.maxActiveGames, !wouldExceedLeagueAllowance else { return }
        let game = Game(
            name: trimmedName,
            season: season,
            allowRepeats: Leagues.app.allowRepeatDefault,
            leagueIds: Array(selectedLeagueIds),
            mode: .killer,
            killerBuildPhaseRounds: killerBuildPhaseRounds,
            killerMaxAdditionalLives: killerMaxAdditionalLives,
            killerMaxMPG: killerMaxMPG
        )
        context.insert(game)
        addManagerIfPlaying(to: game)
        KillerSettings.saveLastUsed(
            buildPhaseRounds: killerBuildPhaseRounds,
            maxAdditionalLives: killerMaxAdditionalLives,
            maxMPG: killerMaxMPG
        )
        dismiss()
    }

    /// Non-completed game count — used as a safety net before insert.
    /// The primary gate is in GamesListView; this prevents a bypass if
    /// NewGameView is ever presented through another path.
    private func activeGameCount() -> Int {
        let completeRaw = GameStatus.complete.rawValue
        let descriptor = FetchDescriptor<Game>(
            predicate: #Predicate { $0.statusRaw != completeRaw }
        )
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    /// The manager plays only if they opted in (they may run games they don't
    /// play in — no ⚑ then). Can still add/remove themselves later in the game.
    private func addManagerIfPlaying(to game: Game) {
        if managerPlaying && !managerTrimmed.isEmpty {
            let player = Player(name: managerTrimmed, game: game, isManager: true,
                                entryNumber: game.nextEntryNumber)
            context.insert(player)
            game.players.append(player)
            KillerScoringService.attachStateIfNeeded(to: player, game: game, context: context)
        }
    }
}

/// UserDefaults-backed "remember last settings" for Predictor's New Game form
/// (§0 decision — implicit prefill, no named/cross-game templates).
enum PredictorSettings {
    private static let defaults = UserDefaults.standard
    private enum Key {
        static let exactPoints = "predictor.lastExactPoints"
        static let gdEnabled = "predictor.lastGDEnabled"
        static let gdPoints = "predictor.lastGDPoints"
        static let resultEnabled = "predictor.lastResultEnabled"
        static let resultPoints = "predictor.lastResultPoints"
        static let jokerEnabled = "predictor.lastJokerEnabled"
    }

    static var lastExactPoints: Int {
        defaults.object(forKey: Key.exactPoints) as? Int ?? 4
    }
    static var lastGDEnabled: Bool {
        defaults.object(forKey: Key.gdEnabled) as? Bool ?? true
    }
    static var lastGDPoints: Int {
        defaults.object(forKey: Key.gdPoints) as? Int ?? 3
    }
    static var lastResultEnabled: Bool {
        defaults.object(forKey: Key.resultEnabled) as? Bool ?? true
    }
    static var lastResultPoints: Int {
        defaults.object(forKey: Key.resultPoints) as? Int ?? 2
    }
    static var lastJokerEnabled: Bool {
        defaults.object(forKey: Key.jokerEnabled) as? Bool ?? false
    }

    // swiftlint:disable:next function_parameter_count
    static func saveLastUsed(
        exactPoints: Int,
        gdEnabled: Bool,
        gdPoints: Int,
        resultEnabled: Bool,
        resultPoints: Int,
        jokerEnabled: Bool
    ) {
        defaults.set(exactPoints, forKey: Key.exactPoints)
        defaults.set(gdEnabled, forKey: Key.gdEnabled)
        defaults.set(gdPoints, forKey: Key.gdPoints)
        defaults.set(resultEnabled, forKey: Key.resultEnabled)
        defaults.set(resultPoints, forKey: Key.resultPoints)
        defaults.set(jokerEnabled, forKey: Key.jokerEnabled)
    }
}

/// UserDefaults-backed "remember last settings" for Killer's New Game form,
/// same pattern as `PredictorSettings`.
enum KillerSettings {
    private static let defaults = UserDefaults.standard
    private enum Key {
        static let buildPhaseRounds = "killer.lastBuildPhaseRounds"
        static let maxAdditionalLives = "killer.lastMaxAdditionalLives"
        static let maxMPG = "killer.lastMaxMPG"
    }

    static var lastBuildPhaseRounds: Int {
        defaults.object(forKey: Key.buildPhaseRounds) as? Int ?? 2
    }
    static var lastMaxAdditionalLives: Int {
        defaults.object(forKey: Key.maxAdditionalLives) as? Int ?? 10
    }
    static var lastMaxMPG: Int {
        defaults.object(forKey: Key.maxMPG) as? Int ?? 5
    }

    static func saveLastUsed(buildPhaseRounds: Int, maxAdditionalLives: Int, maxMPG: Int) {
        defaults.set(buildPhaseRounds, forKey: Key.buildPhaseRounds)
        defaults.set(maxAdditionalLives, forKey: Key.maxAdditionalLives)
        defaults.set(maxMPG, forKey: Key.maxMPG)
    }
}
