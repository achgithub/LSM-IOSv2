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

    /// The local manager's suffix — last 8 hex chars of the manager player's UUID.
    private var localManagerSuffix: String? {
        guard let manager = game.players.first(where: { $0.isManager }) else { return nil }
        return String(manager.id.uuidString.replacingOccurrences(of: "-", with: "").suffix(8)).lowercased()
    }

    @MainActor
    private func applyLocally(_ result: ApproveResult, playerName: String) {
        // Validate that the submission came through an enrollment owned by this manager.
        if let resultSuffix = result.managerSuffix, let localSuffix = localManagerSuffix,
           resultSuffix != localSuffix {
            subQueueLog.warning("Approve skipped: managerSuffix mismatch (\(resultSuffix) ≠ \(localSuffix))")
            return
        }

        // Find player by UUID first; fall back to name for pre-Phase-5 enrollments.
        let player = game.players.first(where: {
            $0.id.uuidString.lowercased() == result.localPlayerId.lowercased()
        }) ?? game.players.first(where: {
            $0.name.localizedCaseInsensitiveCompare(playerName) == .orderedSame
        })
        guard let player else { return }

        if game.mode == .lms, let teamId = result.payload.teamId {
            GameLogicService.setPick(player: player, round: round, teamId: teamId, context: context)
        } else if game.mode == .predictor, let scores = result.payload.scores {
            for score in scores {
                PredictorScoringService.setPrediction(
                    player: player,
                    round: round,
                    fixtureId: score.fixtureId,
                    home: score.home,
                    away: score.away,
                    context: context
                )
            }
            // Apply joker if the player designated one.
            if let jokerScore = scores.first(where: { $0.isJoker == true }) {
                PredictorScoringService.setJoker(player: player, round: round, fixtureId: jokerScore.fixtureId)
            }
        }
    }
}

private struct SubmissionRow: View {
    let item: SubmissionItem
    let game: Game

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(item.playerName).fontWeight(.medium)
                Spacer()
                StatusBadge(status: item.status)
            }
            Text(payloadDescription).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var payloadDescription: String {
        if game.mode == .lms, let teamId = item.payload.teamId {
            let name = item.payload.teamName ?? "Team \(teamId)"
            return "Pick: \(name)"
        } else if let scores = item.payload.scores {
            return scores.map { s in
                s.isJoker == true ? "\(s.home)–\(s.away) ★" : "\(s.home)–\(s.away)"
            }.joined(separator: ", ")
        }
        return "—"
    }
}

private struct StatusBadge: View {
    let status: String
    var body: some View {
        Text(status.capitalized)
            .font(.caption2).fontWeight(.semibold)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
    private var color: Color {
        switch status {
        case "approved": return .green
        case "rejected": return .red
        default: return .orange
        }
    }
}
