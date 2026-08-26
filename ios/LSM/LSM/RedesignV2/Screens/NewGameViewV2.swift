import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Card restyle of `NewGameView`'s mode picker + all three mode forms.
/// Reuses `NewGameView`'s own `Game(...)` construction and the
/// `PredictorSettings`/`KillerSettings` "remember last settings" logic
/// verbatim (copied, not shared, since the original's helpers are private to
/// that view) — no backend/Cloudflare surface changes, this is view-only.
struct NewGameViewV2: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(EnabledLeagues.self) private var enabled
    @AppStorage(ManagerSettings.nameKey) private var managerName = ""

    @State private var mode: GameMode?

    // Import Game (transfer from another manager's device) — see GameTransfer.swift.
    @Query(sort: \RosterMember.name) private var rosterMembers: [RosterMember]
    @State private var showingImport = false
    @State private var importError: String?
    @State private var pendingSnapshot: GameTransferSnapshot?
    @State private var conflictQueue: [GameTransferSnapshot.PlayerSnapshot] = []
    @State private var nameOverrides: [UUID: String] = [:]
    @State private var showingConflictAlert = false
    @State private var currentConflictName = ""

    @State private var name = ""
    @State private var selectedLeagueIds: Set<String> = []
    @State private var managerPlaying = true

    // LMS-only settings.
    @State private var anonymity: AnonymityMode = .anonymous
    @State private var drawEliminates = true
    @State private var postponedEliminates = false

    @State private var predictorExactPoints = PredictorSettings.lastExactPoints
    @State private var predictorGDEnabled = PredictorSettings.lastGDEnabled
    @State private var predictorGDPoints = PredictorSettings.lastGDPoints
    @State private var predictorResultEnabled = PredictorSettings.lastResultEnabled
    @State private var predictorResultPoints = PredictorSettings.lastResultPoints
    @State private var predictorJokerEnabled = PredictorSettings.lastJokerEnabled

    // Killer-only settings.
    @State private var killerBuildPhaseRounds = KillerSettings.lastBuildPhaseRounds
    @State private var killerMaxAdditionalLives = KillerSettings.lastMaxAdditionalLives
    @State private var killerMaxMPG = KillerSettings.lastMaxMPG

    private var managerTrimmed: String { managerName.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var activeLeagueIds: Set<String> {
        let completeRaw = GameStatus.complete.rawValue
        let descriptor = FetchDescriptor<Game>(predicate: #Predicate { $0.statusRaw != completeRaw })
        let games = (try? context.fetch(descriptor)) ?? []
        return Set(games.flatMap(\.leagueIdsRaw))
    }

    private var wouldExceedLeagueAllowance: Bool {
        let newSelections = selectedLeagueIds.subtracting(activeLeagueIds)
        guard !newSelections.isEmpty else { return false }
        return activeLeagueIds.union(selectedLeagueIds).count > Entitlements.shared.leagueAllowance
    }

    private var canCreate: Bool { !trimmedName.isEmpty && !selectedLeagueIds.isEmpty && !wouldExceedLeagueAllowance }

    var body: some View {
        NavigationStack {
            switch mode {
            case .lms: lmsForm
            case .predictor: predictorForm
            case .killer: killerForm
            case nil: modePicker
            }
        }
        .fileImporter(
            isPresented: $showingImport,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
        .alert("Couldn't Import", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? "")
        }
        .alert("Name already in your roster", isPresented: $showingConflictAlert) {
            TextField("Player name", text: $currentConflictName)
            Button("Use this name") { resolveConflict() }
            Button("Cancel Import", role: .cancel) { cancelImport() }
        } message: {
            Text("\"\(conflictQueue.first?.name ?? "")\" matches a player already in your roster. Enter a different name for this import so they aren't mixed up.")
        }
    }

    private var modePicker: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(GameMode.allCases) { candidate in
                    Button {
                        mode = candidate
                        if selectedLeagueIds.isEmpty, enabled.leagues.count == 1 {
                            selectedLeagueIds = Set(enabled.leagues.map(\.id))
                        }
                    } label: {
                        MenuRow(systemImage: modeIcon(candidate), title: candidate.displayName, tint: V2Theme.Mode.color(for: candidate), floating: true)
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    showingImport = true
                } label: {
                    MenuRow(systemImage: "square.and.arrow.down", title: "Import Game", tint: V2Theme.accent, floating: true)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, V2Theme.Spacing.horizontal)
            .padding(.vertical, V2Theme.Spacing.section)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .v2TrophyRoomScene()
        .v2FloatingHeader("New Game", showBack: false) {
            Button("Cancel") { dismiss() }
                .foregroundStyle(V2Theme.textSecondary)
        }
    }

    /// Steps back to the mode picker without dismissing the sheet — visually
    /// distinct (leading chevron, not bare text) from the plain-text Cancel/
    /// Done trailing buttons every other V2 sheet root uses for that reason,
    /// since this one isn't a dismiss.
    private var backToModePickerButton: some View {
        Button { mode = nil } label: {
            Label("Back", systemImage: "chevron.left")
                .labelStyle(.titleAndIcon)
        }
        .foregroundStyle(V2Theme.textSecondary)
    }

    private func modeIcon(_ mode: GameMode) -> String {
        switch mode {
        case .lms: return "figure.walk"
        case .predictor: return "chart.bar.fill"
        case .killer: return "bolt.fill"
        }
    }

    private var predictorForm: some View {
        ScrollView {
            LazyVStack(spacing: V2Theme.Spacing.section) {
                Card(floating: true) {
                    VStack(alignment: .leading, spacing: 10) {
                        MicroLabel(text: "Game name")
                        TextField("e.g. Friday Predictor", text: $name)
                            .textFieldStyle(.plain)
                            .padding(12)
                            .background(V2Theme.pillBackground, in: RoundedRectangle(cornerRadius: V2Theme.Radius.row, style: .continuous))
                    }
                }

                Card(floating: true) {
                    VStack(alignment: .leading, spacing: 10) {
                        MicroLabel(text: "Leagues")
                        FlowPills {
                            ForEach(enabled.leagues) { league in
                                SelectablePill(
                                    title: league.name,
                                    isSelected: selectedLeagueIds.contains(league.id),
                                    tint: V2Theme.Mode.predictor
                                ) {
                                    if enabled.leagues.count > 1 { toggleLeague(league.id) }
                                }
                            }
                        }
                        if wouldExceedLeagueAllowance {
                            Text("Your plan doesn't cover an extra league right now.")
                                .font(.caption).foregroundStyle(V2Theme.danger)
                        }
                    }
                }

                if !managerTrimmed.isEmpty {
                    Card(floating: true) {
                        Toggle(isOn: $managerPlaying) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(managerTrimmed) (you)")
                                    .font(V2Theme.Typography.rowTitle)
                                    .foregroundStyle(V2Theme.textPrimary)
                                Text(managerPlaying ? "Playing in this game" : "Running only, not playing")
                                    .font(.caption).foregroundStyle(V2Theme.textSecondary)
                            }
                        }
                        .tint(V2Theme.Mode.predictor)
                    }
                }

                Card(floating: true) {
                    VStack(alignment: .leading, spacing: 14) {
                        MicroLabel(text: "Scoring")
                        Stepper("Exact score: \(predictorExactPoints) pts", value: $predictorExactPoints, in: 1...10)
                        Divider().background(V2Theme.cardBorder)
                        Toggle("Goal difference", isOn: $predictorGDEnabled).tint(V2Theme.Mode.predictor)
                        if predictorGDEnabled {
                            Stepper("\(predictorGDPoints) pts", value: $predictorGDPoints, in: 1...10)
                        }
                        Divider().background(V2Theme.cardBorder)
                        Toggle("Correct result", isOn: $predictorResultEnabled).tint(V2Theme.Mode.predictor)
                        if predictorResultEnabled {
                            Stepper("\(predictorResultPoints) pts", value: $predictorResultPoints, in: 1...10)
                        }
                        Divider().background(V2Theme.cardBorder)
                        Toggle("Joker (double points, one fixture/round)", isOn: $predictorJokerEnabled)
                            .tint(V2Theme.Mode.predictor)
                        Text("Each prediction earns the single highest rung it qualifies for. A correct non-exact draw lands on Goal difference, not Result.")
                            .font(.caption).foregroundStyle(V2Theme.textTertiary)
                    }
                    .foregroundStyle(V2Theme.textPrimary)
                }

                PrimaryButton(title: "Create Game", isEnabled: canCreate, tint: V2Theme.Mode.predictor) { create() }
            }
            .padding(.horizontal, V2Theme.Spacing.horizontal)
            .padding(.vertical, V2Theme.Spacing.section)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .v2PredictorFormScene()
        .v2FloatingHeader("New Predictor Game", showBack: false) {
            backToModePickerButton
        }
    }

    private func toggleLeague(_ id: String) {
        if selectedLeagueIds.contains(id) { selectedLeagueIds.remove(id) } else { selectedLeagueIds.insert(id) }
    }

    private func create() {
        guard activeGameCount() < Entitlements.shared.maxActiveGames, !wouldExceedLeagueAllowance else { return }
        let game = Game(
            name: trimmedName,
            season: Leagues.app.season,
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
        if managerPlaying && !managerTrimmed.isEmpty {
            let player = Player(name: managerTrimmed, game: game, isManager: true, entryNumber: game.nextEntryNumber)
            context.insert(player)
            game.players.append(player)
        }
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

    private func activeGameCount() -> Int {
        let completeRaw = GameStatus.complete.rawValue
        let descriptor = FetchDescriptor<Game>(predicate: #Predicate { $0.statusRaw != completeRaw })
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    // MARK: - Import Game

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure:
            importError = AppString("Couldn't read that file — it may not be a valid game transfer file.")
        case .success(let urls):
            guard let url = urls.first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let snapshot = try GameTransferFile.read(from: url)
                beginConflictResolution(for: snapshot)
            } catch {
                importError = AppString("Couldn't read that file — it may not be a valid game transfer file.")
            }
        }
    }

    /// Case-insensitive exact match — the same duplicate-name rule used
    /// everywhere else in the app (`PlayersView.isDuplicateMember`, etc.).
    private func beginConflictResolution(for snapshot: GameTransferSnapshot) {
        let existingNames = Set(rosterMembers.map { $0.name.lowercased() })
        pendingSnapshot = snapshot
        nameOverrides = [:]
        conflictQueue = snapshot.players.filter { existingNames.contains($0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) }
        presentNextConflict()
    }

    private func presentNextConflict() {
        guard let next = conflictQueue.first else {
            finishImport()
            return
        }
        currentConflictName = suggestedName(for: next.name)
        showingConflictAlert = true
    }

    private func suggestedName(for name: String) -> String {
        let existingNames = Set(rosterMembers.map { $0.name.lowercased() })
        var suffix = 2
        var candidate = "\(name) (\(suffix))"
        while existingNames.contains(candidate.lowercased())
            || nameOverrides.values.contains(where: { $0.localizedCaseInsensitiveCompare(candidate) == .orderedSame }) {
            suffix += 1
            candidate = "\(name) (\(suffix))"
        }
        return candidate
    }

    private func resolveConflict() {
        guard let current = conflictQueue.first else { return }
        let trimmed = currentConflictName.trimmingCharacters(in: .whitespacesAndNewlines)
        nameOverrides[current.id] = trimmed.isEmpty ? current.name : trimmed
        conflictQueue.removeFirst()
        presentNextConflict()
    }

    private func cancelImport() {
        conflictQueue = []
        pendingSnapshot = nil
    }

    private func finishImport() {
        guard let snapshot = pendingSnapshot else { return }
        GameTransferBuilder.restore(snapshot, nameOverrides: nameOverrides, into: context)
        pendingSnapshot = nil
        dismiss()
    }
}

/// LMS + Killer forms, split into their own extension purely to keep
/// `NewGameViewV2`'s primary declaration under SwiftLint's type_body_length
/// limit — no functional boundary, just file organization.
extension NewGameViewV2 {
    var lmsForm: some View {
        ScrollView {
            LazyVStack(spacing: V2Theme.Spacing.section) {
                Card(floating: true) {
                    VStack(alignment: .leading, spacing: 10) {
                        MicroLabel(text: "Game name")
                        TextField("e.g. Friday LMS", text: $name)
                            .textFieldStyle(.plain)
                            .padding(12)
                            .background(V2Theme.pillBackground, in: RoundedRectangle(cornerRadius: V2Theme.Radius.row, style: .continuous))
                    }
                }

                Card(floating: true) {
                    VStack(alignment: .leading, spacing: 10) {
                        MicroLabel(text: "Leagues")
                        FlowPills {
                            ForEach(enabled.leagues) { league in
                                SelectablePill(
                                    title: league.name,
                                    isSelected: selectedLeagueIds.contains(league.id),
                                    tint: V2Theme.Mode.lms
                                ) {
                                    if enabled.leagues.count > 1 { toggleLeague(league.id) }
                                }
                            }
                        }
                        if wouldExceedLeagueAllowance {
                            Text("Your plan doesn't cover an extra league right now.")
                                .font(.caption).foregroundStyle(V2Theme.danger)
                        }
                    }
                }

                if !managerTrimmed.isEmpty {
                    Card(floating: true) {
                        Toggle(isOn: $managerPlaying) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(managerTrimmed) (you)")
                                    .font(V2Theme.Typography.rowTitle)
                                    .foregroundStyle(V2Theme.textPrimary)
                                Text(managerPlaying ? "Playing in this game" : "Running only, not playing")
                                    .font(.caption).foregroundStyle(V2Theme.textSecondary)
                            }
                        }
                        .tint(V2Theme.Mode.lms)
                    }
                }

                Card(floating: true) {
                    VStack(alignment: .leading, spacing: 14) {
                        MicroLabel(text: "Result rules")
                        Toggle(isOn: $postponedEliminates) {
                            resultRuleLabel("Postponed", eliminates: postponedEliminates)
                        }
                        .tint(V2Theme.Mode.lms)
                        Divider().background(V2Theme.cardBorder)
                        Toggle(isOn: $drawEliminates) {
                            resultRuleLabel("Draw", eliminates: drawEliminates)
                        }
                        .tint(V2Theme.Mode.lms)
                        // swiftlint:disable:next line_length
                        Text("A win always survives and a loss always eliminates. Toggle on for Postponed/Draw to treat them as a loss too — off keeps them as a survive.")
                            .font(.caption).foregroundStyle(V2Theme.textTertiary)
                    }
                    .foregroundStyle(V2Theme.textPrimary)
                }

                Card(floating: true) {
                    VStack(alignment: .leading, spacing: 10) {
                        MicroLabel(text: "Summaries")
                        HStack(spacing: 8) {
                            ForEach(AnonymityMode.allCases) { option in
                                SelectablePill(title: option.label, isSelected: anonymity == option, tint: V2Theme.Mode.lms) {
                                    anonymity = option
                                }
                            }
                        }
                    }
                }

                PrimaryButton(title: "Create Game", isEnabled: canCreate, tint: V2Theme.Mode.lms) { createLMS() }
            }
            .padding(.horizontal, V2Theme.Spacing.horizontal)
            .padding(.vertical, V2Theme.Spacing.section)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .v2LMSFormScene()
        .v2FloatingHeader("New LMS Game", showBack: false) {
            backToModePickerButton
        }
    }

    func resultRuleLabel(_ title: LocalizedStringKey, eliminates: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).foregroundStyle(V2Theme.textPrimary)
            Text(eliminates ? "Counts as a loss" : "Counts as a win")
                .font(.caption).foregroundStyle(V2Theme.textSecondary)
        }
    }

    var killerForm: some View {
        ScrollView {
            LazyVStack(spacing: V2Theme.Spacing.section) {
                Card(floating: true) {
                    VStack(alignment: .leading, spacing: 10) {
                        MicroLabel(text: "Game name")
                        TextField("e.g. Friday Killer", text: $name)
                            .textFieldStyle(.plain)
                            .padding(12)
                            .background(V2Theme.pillBackground, in: RoundedRectangle(cornerRadius: V2Theme.Radius.row, style: .continuous))
                    }
                }

                Card(floating: true) {
                    VStack(alignment: .leading, spacing: 10) {
                        MicroLabel(text: "Leagues")
                        FlowPills {
                            ForEach(enabled.leagues) { league in
                                SelectablePill(
                                    title: league.name,
                                    isSelected: selectedLeagueIds.contains(league.id),
                                    tint: V2Theme.Mode.killer
                                ) {
                                    if enabled.leagues.count > 1 { toggleLeague(league.id) }
                                }
                            }
                        }
                        if wouldExceedLeagueAllowance {
                            Text("Your plan doesn't cover an extra league right now.")
                                .font(.caption).foregroundStyle(V2Theme.danger)
                        }
                    }
                }

                if !managerTrimmed.isEmpty {
                    Card(floating: true) {
                        Toggle(isOn: $managerPlaying) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(managerTrimmed) (you)")
                                    .font(V2Theme.Typography.rowTitle)
                                    .foregroundStyle(V2Theme.textPrimary)
                                Text(managerPlaying ? "Playing in this game" : "Running only, not playing")
                                    .font(.caption).foregroundStyle(V2Theme.textSecondary)
                            }
                        }
                        .tint(V2Theme.Mode.killer)
                    }
                }

                Card(floating: true) {
                    VStack(alignment: .leading, spacing: 14) {
                        MicroLabel(text: "Killer settings")
                        Stepper(killerBuildPhaseRounds == 1
                                ? AppString("Build Phase: \(killerBuildPhaseRounds) round")
                                : AppString("Build Phase: \(killerBuildPhaseRounds) rounds"),
                                value: $killerBuildPhaseRounds, in: 1...10)
                        Divider().background(V2Theme.cardBorder)
                        Stepper("Max additional lives: \(killerMaxAdditionalLives)",
                                value: $killerMaxAdditionalLives, in: 0...20)
                        Divider().background(V2Theme.cardBorder)
                        Stepper("Max Manager Picked Games: \(killerMaxMPG)",
                                value: $killerMaxMPG, in: 1...10)
                        // swiftlint:disable:next line_length
                        Text("Everyone starts with 1 life. During the Build Phase, a correct prediction earns +1 life (up to the cap). After that, the Kill Phase begins: predictions also fire a Hit at a chosen opponent.")
                            .font(.caption).foregroundStyle(V2Theme.textTertiary)
                    }
                    .foregroundStyle(V2Theme.textPrimary)
                }

                PrimaryButton(title: "Create Game", isEnabled: canCreate, tint: V2Theme.Mode.killer) { createKiller() }
            }
            .padding(.horizontal, V2Theme.Spacing.horizontal)
            .padding(.vertical, V2Theme.Spacing.section)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .v2KillerFormScene()
        .v2FloatingHeader("New Killer Game", showBack: false) {
            backToModePickerButton
        }
    }

    func createLMS() {
        guard activeGameCount() < Entitlements.shared.maxActiveGames, !wouldExceedLeagueAllowance else { return }
        let game = Game(
            name: trimmedName,
            season: Leagues.app.season,
            allowRepeats: Leagues.app.allowRepeatDefault,
            anonymityMode: anonymity,
            leagueIds: Array(selectedLeagueIds),
            drawEliminates: drawEliminates,
            postponedEliminates: postponedEliminates,
            mode: .lms
        )
        context.insert(game)
        if managerPlaying && !managerTrimmed.isEmpty {
            let player = Player(name: managerTrimmed, game: game, isManager: true, entryNumber: game.nextEntryNumber)
            context.insert(player)
            game.players.append(player)
        }
        dismiss()
    }

    func createKiller() {
        guard activeGameCount() < Entitlements.shared.maxActiveGames, !wouldExceedLeagueAllowance else { return }
        let game = Game(
            name: trimmedName,
            season: Leagues.app.season,
            allowRepeats: Leagues.app.allowRepeatDefault,
            leagueIds: Array(selectedLeagueIds),
            mode: .killer,
            killerBuildPhaseRounds: killerBuildPhaseRounds,
            killerMaxAdditionalLives: killerMaxAdditionalLives,
            killerMaxMPG: killerMaxMPG
        )
        context.insert(game)
        if managerPlaying && !managerTrimmed.isEmpty {
            let player = Player(name: managerTrimmed, game: game, isManager: true, entryNumber: game.nextEntryNumber)
            context.insert(player)
            game.players.append(player)
            KillerScoringService.attachStateIfNeeded(to: player, game: game, context: context)
        }
        KillerSettings.saveLastUsed(
            buildPhaseRounds: killerBuildPhaseRounds,
            maxAdditionalLives: killerMaxAdditionalLives,
            maxMPG: killerMaxMPG
        )
        dismiss()
    }
}

/// Simple wrapping row layout for pills that may exceed one line (e.g. many
/// leagues) — `HStack` alone would clip or squeeze, and this list is short
/// enough that a manual `Layout` isn't worth it over wrapping in a
/// `ScrollView` when there are more than a handful.
private struct FlowPills<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) { content() }
        }
    }
}
