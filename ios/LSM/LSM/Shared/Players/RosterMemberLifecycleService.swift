import Foundation
import SwiftData
import os

private let rosterLifecycleLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "lsm", category: "roster-lifecycle")

/// Deletes a roster member locally and, if they had a live submission link,
/// fires a best-effort revoke so the link stops working — the inverse of
/// `GameLogicService.deleteGame`, which deliberately leaves player tokens
/// alone (a game delete shouldn't kill a link shared with other games).
/// Here the player record itself is going away, so nobody should be able to
/// keep submitting through the old link.
enum RosterMemberLifecycleService {
    static func delete(_ member: RosterMember, context: ModelContext) {
        let token = member.submissionTokenRaw
        context.delete(member)
        guard let token else { return }
        Task {
            do {
                try await SubmissionsClient.shared.revokeLink(token: token)
            } catch {
                rosterLifecycleLog.warning("Revoke failed for deleted player's link: \(error.localizedDescription)")
            }
        }
    }
}
