import SwiftUI

/// Predictor mode home (NEW in v2) — **skeleton**.
///
/// Each week, players predict the scoreline of each fixture in scope; points are
/// awarded per fixture (working example: 1 correct outcome + 1 correct home score
/// + 1 correct away score) and accumulate into a season-long league table. Unlike
/// LMS there is no elimination — players can join/leave mid-season. Cloud-backed
/// from day one (predictions live in D1, not on-device).
///
/// Gameplay is not built yet; this view is the placeholder the Modes/Predictor
/// folder hangs off. See docs/lsm-v2-architecture.md §1 (Predictor) and the
/// `predictions` table in worker/schema.sql.
struct PredictorHomeView: View {
    var body: some View {
        ContentUnavailableView(
            "Predictor",
            systemImage: "sportscourt",
            description: Text("Season-long score prediction. Coming in v2 — skeleton, gameplay not built yet.")
        )
    }
}

#Preview {
    PredictorHomeView()
}
