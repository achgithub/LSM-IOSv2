import SwiftUI
import SwiftData
import OSLog

private let inboxLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "lsm", category: "submissions")

/// V2's submission queue: a single view backing two entry points.
/// - `filterGameToken == nil` — the central inbox, reached from Games'
///   SUBMISSIONS tile, showing pending submissions across every game grouped
///   into color-coded sections (`V2Theme.GameIdentity`).
/// - `filterGameToken` set — the same view pre-filtered to one game, reached
///   from that game's detail screen, replacing V1's per-game
///   `SubmissionQueueView` for V2 only (V1 keeps using that view unchanged).
///
/// Always backed by one aggregate network call (`listPendingSubmissions`),
/// never a per-game fan-out, whichever entry point it's reached from.
///
/// Rows are tap-to-open, not swipe-only — a leading-edge swipe action fights
/// the NavigationStack's interactive-pop gesture (still live even though
/// `V2FloatingHeader` hides the system back *button*), so it isn't a
/// reliable way to expose Approve/Reject. A tap always works and gives room to show full
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
        ScrollView {
            LazyVStack(alignment: .leading, spacing: V2Theme.Spacing.section) {
                if isLoading && items.isEmpty {
                    Color.clear.frame(height: 200)
                } else if let errorMessage {
                    Card(floating: true) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(errorMessage).foregroundStyle(V2Theme.textSecondary)
                            Button("Retry") { Task { await load() } }
                                .foregroundStyle(V2Theme.accent)
                        }
                    }
                } else if visibleItems.isEmpty {
                    Card(floating: true) {
                        Text("No pending submissions.").foregroundStyle(V2Theme.textSecondary)
                    }
                } else if filterGameToken != nil {
                    VStack(spacing: 10) {
                        ForEach(visibleItems) { item in row(for: item) }
                    }
                } else {
                    ForEach(groupedByGame, id: \.gameToken) { bucket in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(V2Theme.GameIdentity.color(for: bucket.gameToken))
                                    .frame(width: 8, height: 8)
                                Text(bucket.items.first?.gameName ?? "Game")
                                    .font(V2Theme.Typography.sectionHeading)
                                    .foregroundStyle(V2Theme.textPrimary)
                            }
                            VStack(spacing: 10) {
                                ForEach(bucket.items) { item in row(for: item) }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, V2Theme.Spacing.horizontal)
            .padding(.vertical, V2Theme.Spacing.section)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .v2TrophyRoomScene()
        .v2LoadingOverlay(isLoading && items.isEmpty, label: "Loading submissions…")
        .v2FloatingHeader(filterGameToken != nil ? "Submission Queue" : "Submissions")
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
                .padding(16)
                .v2FloatingCard()
            } else {
                SubmissionRow(item: item, game: game)
                    .padding(16)
                    .v2FloatingCard()
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

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(V2Theme.textSecondary)
            Spacer()
            Text(value).foregroundStyle(V2Theme.textPrimary)
        }
        .font(V2Theme.Typography.metadata)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: V2Theme.Spacing.section) {
                    Card(floating: true) {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(title: "Submission")
                            detailRow("Player", item.playerName)
                            detailRow("Game", game?.name ?? item.gameName ?? AppString("Unknown"))
                            if let mode {
                                detailRow("Mode", mode.displayName)
                            }
                            detailRow("Round", "\(item.roundNumber)")
                        }
                    }
                    if onApprove == nil {
                        Card(floating: true) {
                            Text("This looks like a submission for a game you no longer have. You can only delete it.")
                                .foregroundStyle(V2Theme.textSecondary)
                        }
                    } else {
                        Card(floating: true) {
                            VStack(alignment: .leading, spacing: 10) {
                                SectionHeader(title: "Picks")
                                SubmissionRow(item: item, game: game)
                            }
                        }
                    }
                    if let onApprove {
                        PrimaryButton(title: "Approve") {
                            onApprove()
                            dismiss()
                        }
                    }
                    ActionRow(
                        title: onApprove == nil ? "Delete" : "Reject",
                        icon: "xmark.circle.fill",
                        tint: V2Theme.danger
                    ) {
                        onDelete()
                        dismiss()
                    }
                    .padding(16)
                    .v2FloatingCard()
                }
                .padding(.horizontal, V2Theme.Spacing.horizontal)
                .padding(.vertical, V2Theme.Spacing.section)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .v2TrophyRoomScene()
            .v2FloatingHeader("Submission", showBack: false) {
                Button("Close") { dismiss() }
                    .foregroundStyle(V2Theme.textSecondary)
            }
        }
    }
}
