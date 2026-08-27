import SwiftUI
import SwiftData

/// Shared "where's this game's round state right now" — reduces the three
/// game-detail screens' near-identical `currentRound`/`openRound`/
/// `latestClosedRound`/`sortedPlayers` blocks to one implementation (see V2
/// audit 3.1). A plain wrapper around a reference (`Game` is a SwiftData
/// model, so this owns no state of its own) — each property recomputes
/// fresh off `game.rounds`/`game.players` on read, same as the four
/// computed vars it replaces, so this is cost-neutral versus what was here
/// before (per `ios/LSM/CLAUDE.md`'s per-render-cost check).
struct V2GameRoundContext {
    let game: Game

    var currentRound: Round? { game.currentRound }
    var openRound: Round? {
        if let round = currentRound, round.status != .closed { return round }
        return nil
    }
    var latestClosedRound: Round? {
        game.rounds.filter { $0.status == .closed }.max(by: { $0.roundNumber < $1.roundNumber })
    }
    var sortedPlayers: [Player] {
        game.players.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

/// The two "Export" menu actions shared by every game-detail screen's
/// header — CSV backup (the one mode-specific piece: which `*ExportFiles`
/// writer to call) and the full-fidelity transfer file (identical for all
/// three modes, so it isn't switched on `self` at all). See V2 audit 3.1.
enum V2GameExporter {
    case lms, predictor, killer

    /// Manual backup: the game's settings + full prediction/pick history as
    /// CSV files via the share sheet.
    func exportGame(_ game: Game) async throws -> [URL] {
        let data = try await LeagueData.load(for: game.leagues)
        switch self {
        case .lms: return try GameExportFiles.write(for: game, data: data)
        case .predictor: return try PredictorExportFiles.write(for: game, data: data)
        case .killer: return try KillerExportFiles.write(for: game, data: data)
        }
    }

    /// Full-fidelity JSON hand-off to another manager — not the CSV backup
    /// above. PWA links never transfer; the receiving manager mints fresh
    /// ones if they use PWA submissions.
    func exportForTransfer(_ game: Game) throws -> [URL] {
        [try GameTransferFile.write(snapshot: GameTransferBuilder.snapshot(of: game), gameName: game.name)]
    }
}

/// State + actions behind the export/rename header controls shared by every
/// game-detail screen. Own one as `@State private var headerActions =
/// V2GameHeaderActionsModel(exporter: .lms)` (pick the matching mode) in the
/// screen, place `V2GameHeaderActions(game:model:)` in the header's
/// trailing closure, and apply `.v2GameHeaderActions(game:model:)` on the
/// screen itself for the rename alert + export sheet/error alert that go
/// with it. Factored out after the same ~75-line block (trailing content,
/// rename alert, export sheet, export-failed alert, `commitRename()`,
/// `exportGame()`/`exportForTransfer()`) had been hand-rolled three times
/// over — see V2 audit 3.1.
@Observable
final class V2GameHeaderActionsModel {
    let exporter: V2GameExporter
    var renaming = false
    var renameText = ""
    var isPreparingExport = false
    var exportFiles: [URL]?
    var exportError: String?
    /// Round-correction wizard entry point — see `RoundCorrectionWizardView`'s
    /// doc comment for why this lives buried in this same menu rather than as
    /// a first-class button.
    var showingCorrectionWizard = false

    init(exporter: V2GameExporter) {
        self.exporter = exporter
    }

    func beginRename(current name: String) {
        renameText = name
        renaming = true
    }

    func commitRename(on game: Game, context: ModelContext) {
        let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        game.name = name
        try? context.save()
    }

    func exportCSV(for game: Game) async {
        isPreparingExport = true
        defer { isPreparingExport = false }
        do {
            exportFiles = try await exporter.exportGame(game)
        } catch {
            exportError = AppString("Couldn't prepare the export. Please try again.")
        }
    }

    func exportForTransfer(_ game: Game) async {
        isPreparingExport = true
        defer { isPreparingExport = false }
        do {
            exportFiles = try exporter.exportForTransfer(game)
        } catch {
            exportError = AppString("Couldn't prepare the export. Please try again.")
        }
    }
}

/// Header trailing content: export `Menu` + rename pencil, both the
/// `V2HeaderIconButton`/`V2HeaderIconLabel` circular treatment. Pair with
/// `.v2GameHeaderActions(game:model:)` on the screen for the alerts/sheet
/// this drives.
struct V2GameHeaderActions: View {
    let game: Game
    var model: V2GameHeaderActionsModel

    var body: some View {
        HStack(spacing: 10) {
            if model.isPreparingExport {
                ProgressView()
            } else {
                Menu {
                    Button { Task { await model.exportCSV(for: game) } } label: {
                        Label("Export as CSV (backup)", systemImage: "doc.text")
                    }
                    Button { Task { await model.exportForTransfer(game) } } label: {
                        Label("Export for Transfer", systemImage: "square.and.arrow.up.on.square")
                    }
                    Divider()
                    Button { model.showingCorrectionWizard = true } label: {
                        Label("Fix a Player's History", systemImage: "wrench.and.screwdriver")
                    }
                } label: {
                    V2HeaderIconLabel(systemImage: "square.and.arrow.up")
                }
            }
            V2HeaderIconButton(systemImage: "pencil") {
                model.beginRename(current: game.name)
            }
        }
    }
}

private struct V2GameHeaderActionsModifier: ViewModifier {
    let game: Game
    @Bindable var model: V2GameHeaderActionsModel
    @Environment(\.modelContext) private var context

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $model.showingCorrectionWizard) {
                RoundCorrectionWizardView(game: game)
            }
            .alert("Rename game", isPresented: $model.renaming) {
                TextField("Game name", text: $model.renameText)
                Button("Rename") { model.commitRename(on: game, context: context) }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(item: Binding(
                get: { model.exportFiles.map(ExportShareItem.init) },
                set: { if $0 == nil { model.exportFiles = nil } }
            )) { item in
                ActivityShareView(items: item.urls)
            }
            .alert("Export Failed", isPresented: Binding(
                get: { model.exportError != nil },
                set: { if !$0 { model.exportError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.exportError ?? "")
            }
    }
}

extension View {
    /// Rename alert + export sheet/error alert driven by a
    /// `V2GameHeaderActionsModel` — pair with `V2GameHeaderActions` in the
    /// header's trailing closure.
    func v2GameHeaderActions(game: Game, model: V2GameHeaderActionsModel) -> some View {
        modifier(V2GameHeaderActionsModifier(game: game, model: model))
    }
}

/// One player row inside a game-detail screen's Players card — name, "you"
/// badge, PWA link glyph, and (only when `showsStatus` is set) a trailing
/// win/eliminated status label. Tapping a roster-linked player opens
/// `PlayerDetailViewV2` — same screen `PlayersViewV2` links to — so link
/// mint/regenerate/remove queries can be handled right from the game
/// without a trip to the Players tab; a player with no roster member
/// (manager's own entry, or typed directly with no link possible) renders
/// inert, no tap.
///
/// Absorbs the LMS-only `PlayerRowV2` and Predictor/Killer's identical
/// `playerRowContent` — those differed only in this one optional suffix
/// (see V2 audit 3.1/3.7). No behavior change: Predictor and Killer still
/// pass `showsStatus: false` (the default), so this doesn't newly surface
/// Killer's elimination state here — that's a real gap (Killer players can
/// be eliminated same as LMS, but this row never showed it even before this
/// refactor), just not one this pass fixes.
struct V2GamePlayerRow: View {
    let player: Player
    let member: RosterMember?
    let pwaEnabled: Bool
    let tint: Color
    var showsStatus: Bool = false

    var body: some View {
        if let member {
            NavigationLink {
                PlayerDetailViewV2(member: member, pwaEnabled: pwaEnabled)
            } label: {
                content
            }
            .buttonStyle(.plain)
        } else {
            content
        }
    }

    private var content: some View {
        HStack {
            Text(player.name)
                .font(V2Theme.Typography.rowTitle)
                .foregroundStyle(V2Theme.textPrimary)
            if player.isManager {
                V2StatusBadge(label: "you", tint: tint)
            }
            Spacer()
            if pwaEnabled, let member {
                Image(systemName: member.submissionTokenRaw != nil ? "link" : "plus.circle")
                    .font(.caption)
                    .foregroundStyle(V2Theme.textSecondary)
            }
            if showsStatus, player.status != .active {
                Text(player.status.label)
                    .font(.caption)
                    .foregroundStyle(player.status == .winner ? V2Theme.accent : V2Theme.danger)
            }
        }
        .padding(10)
        .background(V2Theme.pillBackground, in: RoundedRectangle(cornerRadius: V2Theme.Radius.row, style: .continuous))
    }
}

/// The "current player, tap to switch" card at the top of a one-player-at-
/// a-time entry screen — used by `PredictionsEntryViewV2` and
/// `KillerPredictionsEntryViewV2`, identical apart from what each considers
/// "complete" for the checkmark (see V2 audit 3.4).
struct V2EntryPlayerCard: View {
    let name: String
    let isComplete: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Card(padding: 14, floating: true) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        MicroLabel(text: "Player")
                        Text(name)
                            .font(V2Theme.Typography.rowTitle)
                            .foregroundStyle(V2Theme.textPrimary)
                    }
                    Spacer()
                    if isComplete {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(V2Theme.accent)
                    }
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(V2Theme.textSecondary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

/// "Players (N)" card shared by every game-detail screen: header, empty
/// state, row list with remove-via-context-menu, "Add Players" action. See
/// V2 audit 3.1.
struct V2GamePlayersCard: View {
    let players: [Player]
    let tint: Color
    let pwaEnabled: Bool
    /// Only LMS shows the trailing win/eliminated suffix — see
    /// `V2GamePlayerRow.showsStatus`.
    var showsStatus: Bool = false
    /// Applied to "Add Players" only when non-nil — Predictor's screen
    /// carries a tutorial anchor here that LMS/Killer don't.
    var addPlayersTutorialAnchorId: String?
    let rosterMember: (Player) -> RosterMember?
    let onRemove: (Player) -> Void
    let onAdd: () -> Void

    var body: some View {
        Card(floating: true) {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Players (\(players.count))")
                if players.isEmpty {
                    Text("No players yet.").font(.footnote).foregroundStyle(V2Theme.textSecondary)
                } else {
                    VStack(spacing: 8) {
                        ForEach(players) { player in
                            V2GamePlayerRow(
                                player: player,
                                member: rosterMember(player),
                                pwaEnabled: pwaEnabled,
                                tint: tint,
                                showsStatus: showsStatus
                            )
                            .contextMenu {
                                Button(role: .destructive) { onRemove(player) } label: {
                                    Label("Remove", systemImage: "person.fill.xmark")
                                }
                            }
                        }
                    }
                }
                addPlayersRow
            }
        }
    }

    @ViewBuilder
    private var addPlayersRow: some View {
        let row = ActionRow(title: "Add Players", icon: "person.badge.plus", action: onAdd)
        if let id = addPlayersTutorialAnchorId {
            row.tutorialAnchor(id: id)
        } else {
            row
        }
    }
}
