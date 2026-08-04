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
struct SubmissionInboxViewV2: View {
    @Environment(\.modelContext) private var context
    @Query private var games: [Game]

    var filterGameToken: UUID?

    @State private var items: [SubmissionItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

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
    }

    @ViewBuilder
    private func row(for item: SubmissionItem) -> some View {
        // A pending item whose game token doesn't match anything local can't
        // be applied (no Game/Round to write picks into) — skip it rather
        // than show a row that can't act, mirroring the existing stale-round
        // guard in `SubmissionApplyService`.
        if let token = item.gameToken, let game = localGame(forTokenString: token) {
            SubmissionRow(item: item, game: game)
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button("Approve") { Task { await approve(item, game: game) } }
                        .tint(.green)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button("Reject", role: .destructive) { Task { await reject(item) } }
                }
        }
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
