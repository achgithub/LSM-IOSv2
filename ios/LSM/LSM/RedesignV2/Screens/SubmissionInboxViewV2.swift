import SwiftUI
import SwiftData
import OSLog

private let inboxLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "lsm", category: "submissions")

/// V2's submission queue: a single view backing two entry points.
/// - `filterGameToken == nil` — the central inbox, reached from the Home/
///   Games bell, showing pending submissions across every game grouped into
///   color-coded sections (`V2Theme.GameIdentity`).
/// - `filterGameToken` set — the same view pre-filtered to one game, reached
///   from that game's detail screen, replacing V1's per-game
///   `SubmissionQueueView` for V2 only (V1 keeps using that view unchanged).
///
/// Always backed by one aggregate network call (`listPendingSubmissions`),
/// never a per-game fan-out, whichever entry point it's reached from.
///
/// Rows are tap-to-open, not swipe-only — a leading-edge swipe action fights
/// the NavigationStack's interactive-pop gesture (still live even though
/// `AppHeader` hides the system back *button*), so it isn't a reliable way
/// to expose Approve/Reject. A tap always works and gives room to show full
/// submission detail instead of a truncated one-line summary.
struct SubmissionInboxViewV2: View {
    @Environment(\.modelContext) private var context
    @Query private var games: [Game]

    var filterGameToken: UUID?

    @State private var items: [SubmissionItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selection: SelectedSubmission?

    private var visibleItems: [SubmissionItem] {
        guard let filterGameToken else { return items }
        let tokenString = filterGameToken.uuidString.lowercased()
        return items.filter { $0.gameToken?.lowercased() == tokenString }
    }

    /// Preserves submission order (oldest first, as returned by the server)
    /// within each game's bucket while grouping into sections.
    private var groupedByGame: [(gameToken: String, items: [SubmissionItem])] {
        var order: [String] = []
        var buckets: [String: [SubmissionItem]] = [:]
        for item in visibleItems {
            guard let token = item.gameToken else { continue }
            if buckets[token] == nil { order.append(token) }
            buckets[token, default: []].append(item)
        }
        return order.map { ($0, buckets[$0] ?? []) }
    }

    private func localGame(forTokenString token: String) -> Game? {
        games.first { $0.cloudGameToken?.uuidString.lowercased() == token.lowercased() }
    }

    var body: some View {
        List {
            if isLoading && items.isEmpty {
                ProgressView("Loading submissions…")
            } else if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(V2Theme.textSecondary)
                    Button("Retry") { Task { await load() } }
                }
            } else if visibleItems.isEmpty {
                Section {
                    Text("No pending submissions.").foregroundStyle(V2Theme.textSecondary)
                }
            } else if filterGameToken != nil {
                Section {
                    ForEach(visibleItems) { item in row(for: item) }
                }
            } else {
                ForEach(groupedByGame, id: \.gameToken) { bucket in
                    Section {
                        ForEach(bucket.items) { item in row(for: item) }
                    } header: {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(V2Theme.GameIdentity.color(for: bucket.gameToken))
                                .frame(width: 8, height: 8)
                            Text(bucket.items.first?.gameName ?? "Game")
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(V2Theme.background.ignoresSafeArea())
        .v2Header(filterGameToken != nil ? "Submission Queue" : "Submissions")
        .refreshable { await load() }
        .task { await load() }
        .sheet(item: $selection) { selected in
            SubmissionDetailSheet(
                item: selected.item,
                game: selected.game,
                onApprove: selected.game.map { game in { Task { await approve(selected.item, game: game) } } },
                onDelete: { Task { await reject(selected.item) } }
            )
        }
    }

    @ViewBuilder
    private func row(for item: SubmissionItem) -> some View {
        let game = item.gameToken.flatMap(localGame(forTokenString:))
        Button {
            selection = SelectedSubmission(item: item, game: game)
        } label: {
            if item.gameToken != nil, game == nil {
                // The submission's gameToken doesn't match anything on this
                // device (e.g. the game was deleted locally, or reinstalled
                // without this cloud link). Nothing to apply an approval to,
                // so this row exists purely to be deleted.
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.playerName).fontWeight(.medium)
                    Text("This looks like a submission for a game you no longer have.")
                        .font(.caption)
                        .foregroundStyle(V2Theme.danger)
                }
            } else {
                SubmissionRow(item: item, game: game)
            }
        }
        .buttonStyle(.plain)
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            items = try await SubmissionsClient.shared.listPendingSubmissions()
        } catch {
            errorMessage = "Couldn't load submissions: \(error.localizedDescription)"
        }
        isLoading = false
    }

    private func approve(_ item: SubmissionItem, game: Game) async {
        guard let tokenString = item.gameToken, let gameToken = UUID(uuidString: tokenString) else { return }
        do {
            let result = try await SubmissionsClient.shared.approve(submissionId: item.id, gameToken: gameToken)
            if let round = game.currentRound, round.status != .closed {
                await MainActor.run {
                    SubmissionApplyService.apply(result, playerName: item.playerName, game: game, round: round, context: context)
                }
            }
            await load()
            await SubmissionBadgeStore.shared.refresh()
        } catch {
            inboxLog.warning("Approve failed: \(error.localizedDescription)")
        }
    }

    /// Also the delete path for an orphaned submission — the server-side
    /// reject doesn't require a local game to exist, only the gameToken the
    /// item already carries.
    private func reject(_ item: SubmissionItem) async {
        guard let tokenString = item.gameToken, let gameToken = UUID(uuidString: tokenString) else { return }
        do {
            try await SubmissionsClient.shared.reject(submissionId: item.id, gameToken: gameToken)
            await load()
            await SubmissionBadgeStore.shared.refresh()
        } catch {
            inboxLog.warning("Reject failed: \(error.localizedDescription)")
        }
    }
}

private struct SelectedSubmission: Identifiable {
    let item: SubmissionItem
    let game: Game?
    var id: String { item.id }
}

/// Full detail for one submission plus explicit Approve/Reject buttons —
/// the primary way to act on a submission (see `SubmissionInboxViewV2`'s
/// doc comment for why this replaced swipe-only actions). `onApprove` is
/// nil for an orphaned submission (no local game to apply it to); Delete
/// is always available since rejecting only needs the gameToken.
private struct SubmissionDetailSheet: View {
    let item: SubmissionItem
    let game: Game?
    let onApprove: (() -> Void)?
    let onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss

    private var mode: GameMode? {
        game?.mode ?? item.mode.flatMap(GameMode.init(rawValue:))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Player", value: item.playerName)
                    LabeledContent("Game", value: game?.name ?? item.gameName ?? AppString("Unknown"))
                    if let mode {
                        LabeledContent("Mode", value: mode.displayName)
                    }
                    LabeledContent("Round", value: "\(item.roundNumber)")
                }
                if onApprove == nil {
                    Section {
                        Text("This looks like a submission for a game you no longer have. You can only delete it.")
                            .foregroundStyle(V2Theme.textSecondary)
                    }
                } else {
                    Section("Submission") {
                        SubmissionRow(item: item, game: game)
                    }
                }
                Section {
                    if let onApprove {
                        Button {
                            onApprove()
                            dismiss()
                        } label: {
                            Label("Approve", systemImage: "checkmark.circle.fill")
                        }
                        .foregroundStyle(.green)
                    }
                    Button(role: .destructive) {
                        onDelete()
                        dismiss()
                    } label: {
                        Label(onApprove == nil ? "Delete" : "Reject", systemImage: "xmark.circle.fill")
                    }
                }
            }
            .navigationTitle("Submission")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}
