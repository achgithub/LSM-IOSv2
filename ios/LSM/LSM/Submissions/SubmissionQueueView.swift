import SwiftUI

/// The manager's approve/reject queue (NEW in v2) — **skeleton**.
///
/// Players submit picks (LMS) or score predictions (Predictor) through their
/// anonymous PWA link (no email, no account — the unguessable UUID is the
/// credential). Submissions land here as *pending*; they do NOT become live
/// picks/predictions until the manager approves. Approval is what writes the real
/// row; rejection discards. Manager-typed entries skip this queue entirely (the
/// permanent fallback for players who never self-submit).
///
/// Not wired yet — backed by `GameCloudClient.pendingSubmissions` / `.decide`,
/// both stubbed. See docs/lsm-v2-architecture.md §3 and
/// worker/src/routes/submissions.ts.
struct SubmissionQueueView: View {
    var body: some View {
        ContentUnavailableView(
            "No pending submissions",
            systemImage: "tray",
            description: Text("Picks and predictions submitted via players' PWA links appear here for approval. Skeleton — not wired yet.")
        )
    }
}

#Preview {
    SubmissionQueueView()
}
