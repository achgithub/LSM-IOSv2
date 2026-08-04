import SwiftUI
import SwiftData
import OSLog

private let subQueueLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "lsm", category: "submissions")

/// Submission approval queue for the current open round. Shows each player's
/// pending self-submitted pick (LMS) or score slate (Predictor). Approve writes
/// the real local Pick/Prediction immediately; reject discards the submission.
/// Current-round only — rolling history is a fast-follow.
struct SubmissionQueueView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let game: Game
    let round: Round
    let gameToken: UUID

    @State private var items: [SubmissionItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var isApprovingAll = false

    var pendingItems: [SubmissionItem] { items.filter { $0.status == "pending" } }

    var body: some View {
        List {
            if isLoading && items.isEmpty {
                ProgressView("Loading submissions…")
            } else if let error = errorMessage {
                Section {
                    Text(error).foregroundStyle(.secondary)
                    Button("Retry") { Task { await load() } }
                }
            } else if items.isEmpty {
                Section {
                    Text("No submissions yet for round \(round.roundNumber).")
                        .foregroundStyle(.secondary)
                }
            } else {
                if !pendingItems.isEmpty {
                    Section {
                        Button("Approve all pending (\(pendingItems.count))") {
                            Task { await approveAll() }
                        }
                        .disabled(isApprovingAll)
                    }
                }
                Section("Submissions — Round \(round.roundNumber)") {
                    ForEach(items) { item in
                        SubmissionRow(item: item, game: game)
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                if item.status == "pending" {
                                    Button("Approve") { Task { await approve(item) } }
                                        .tint(.green)
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if item.status == "pending" {
                                    Button("Reject", role: .destructive) { Task { await reject(item) } }
                                }
                            }
                    }
                }
            }
        }
        .navigationTitle("Submission Queue")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
            ToolbarItem(placement: .primaryAction) {
                Button { Task { await load() } } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(isLoading)
            }
        }
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            items = try await SubmissionsClient.shared.listSubmissions(
                gameToken: gameToken,
                round: round.roundNumber
            )
        } catch APIError.badStatus(404, _) {
            // The worker 404s "game not found" when no `round_pushes` row
            // exists yet for this game — i.e. this round was never actually
            // sent to players (cloudGameToken can be set locally before the
            // push that creates that row succeeds). Point at the fix rather
            // than showing a generic network error.
            errorMessage = AppString("This round hasn't been sent to players yet. Use \"Resend to Player App\" on the game screen, then try again.")
        } catch {
            errorMessage = "Couldn't load submissions: \(error.localizedDescription)"
        }
        isLoading = false
    }

    private func approve(_ item: SubmissionItem) async {
        do {
            let result = try await SubmissionsClient.shared.approve(submissionId: item.id, gameToken: gameToken)
            await MainActor.run { applyLocally(result, playerName: item.playerName) }
            await load()
        } catch {
            subQueueLog.warning("Approve failed: \(error.localizedDescription)")
        }
    }

    private func reject(_ item: SubmissionItem) async {
        do {
            try await SubmissionsClient.shared.reject(submissionId: item.id, gameToken: gameToken)
            await load()
        } catch {
            subQueueLog.warning("Reject failed: \(error.localizedDescription)")
        }
    }

    private func approveAll() async {
        isApprovingAll = true
        for item in pendingItems {
            do {
                let result = try await SubmissionsClient.shared.approve(submissionId: item.id, gameToken: gameToken)
                await MainActor.run { applyLocally(result, playerName: item.playerName) }
            } catch {
                subQueueLog.warning("Approve-all partial failure for \(item.id): \(error.localizedDescription)")
            }
        }
        isApprovingAll = false
        await load()
    }

    @MainActor
    private func applyLocally(_ result: ApproveResult, playerName: String) {
        SubmissionApplyService.apply(result, playerName: playerName, game: game, round: round, context: context)
    }
}

struct SubmissionRow: View {
    let item: SubmissionItem
    /// Nil when this item's `gameToken` doesn't resolve to any game on this
    /// device (see `SubmissionInboxViewV2`'s orphaned-submission handling) —
    /// falls back to the aggregate endpoint's `item.mode` string for mode-
    /// specific rendering, and skips Killer target-name lookup (needs
    /// `game.players`).
    let game: Game?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(item.playerName).fontWeight(.medium)
                Spacer()
                StatusBadge(status: item.status)
            }
            pickDetail
        }
        .padding(.vertical, 2)
    }

    /// LMS shows the picked team big, its opponent small underneath (no
    /// truncation — the row grows to fit rather than hiding it behind a tap).
    private var mode: GameMode? {
        game?.mode ?? item.mode.flatMap(GameMode.init(rawValue:))
    }

    @ViewBuilder
    private var pickDetail: some View {
        if mode == .lms, let teamId = item.payload.teamId {
            let name = item.payload.teamName ?? "Team \(teamId)"
            VStack(alignment: .leading, spacing: 0) {
                Text(name).font(.subheadline).fontWeight(.semibold)
                if let opponent = item.payload.opponentName {
                    Text("v \(opponent)").font(.caption).foregroundStyle(.secondary)
                }
            }
        } else if let scores = item.payload.scores {
            Text(scores.map { s in
                s.isJoker == true ? "\(s.home)–\(s.away) ★" : "\(s.home)–\(s.away)"
            }.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
        } else if let outcomes = item.payload.outcomes {
            Text(outcomes.map { entry -> String in
                let abbrev = Self.abbreviation(for: entry.outcome)
                guard let targetIdString = entry.hitTargetId,
                      let targetId = UUID(uuidString: targetIdString),
                      let target = game?.players.first(where: { $0.id == targetId }) else { return abbrev }
                return "\(abbrev)→\(target.name)"
            }.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
        } else {
            Text("—").font(.caption).foregroundStyle(.secondary)
        }
    }

    private static func abbreviation(for rawOutcome: String) -> String {
        switch rawOutcome {
        case "homeWin": return "H"
        case "draw": return "D"
        case "awayWin": return "A"
        default: return "?"
        }
    }
}

private struct StatusBadge: View {
    let status: String
    var body: some View {
        Text(label)
            .font(.caption2).fontWeight(.semibold)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
    /// `status.capitalized` on the raw API value ("pending"/"approved"/
    /// "rejected") never localizes — `Text(String)` only localizes literals.
    /// Route through `AppString` like the model-layer `.label` computed
    /// properties do (`GameStatus.label`, `PlayerStatus.label`, etc.).
    private var label: String {
        switch status {
        case "approved": return AppString("Approved")
        case "rejected": return AppString("Rejected")
        default: return AppString("Pending")
        }
    }
    private var color: Color {
        switch status {
        case "approved": return .green
        case "rejected": return .red
        default: return .orange
        }
    }
}
