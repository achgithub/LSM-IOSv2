import SwiftUI

/// Custom V2 header: circular translucent back button + centered bold title,
/// replacing the system nav bar look. Still a real NavigationStack toolbar —
/// `dismiss()` on a pushed screen, swipe-back gesture untouched — just
/// restyled, so no custom navigation stack to maintain.
struct AppHeader: ToolbarContent {
    let title: String
    /// Submission-queue badge count, shown as a trailing bell icon when > 0.
    /// Currently always a caller-supplied mock (no live submission count is
    /// wired up yet) — see `SubmissionsClient`/`SubmissionQueueView` for the
    /// real per-game/round data this should eventually aggregate.
    var trailingBadgeCount: Int?
    @Environment(\.dismiss) private var dismiss

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(V2Theme.textPrimary)
                    .frame(width: 36, height: 36)
                    .background(V2Theme.cardBackground, in: Circle())
            }
            .accessibilityLabel("Back")
        }
        ToolbarItem(placement: .principal) {
            Text(title)
                .font(V2Theme.Typography.pageTitle)
                .foregroundStyle(V2Theme.textPrimary)
        }
        if let trailingBadgeCount, trailingBadgeCount > 0 {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    // No destination yet — badge is a visual mock until the
                    // submission queue is aggregated across games.
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "bell.fill")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(V2Theme.textPrimary)
                            .frame(width: 36, height: 36)
                            .background(V2Theme.cardBackground, in: Circle())
                        Text("\(trailingBadgeCount)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(4)
                            .background(V2Theme.danger, in: Circle())
                            .offset(x: 6, y: -6)
                    }
                }
                .accessibilityLabel("Submission queue: \(trailingBadgeCount) pending")
            }
        }
    }
}

extension View {
    /// Applies the V2 header for a pushed screen: hides the system back
    /// button/title (AppHeader supplies its own) and paints the nav bar to
    /// match the V2 background so there's no seam above the content.
    func v2Header(_ title: String, trailingBadgeCount: Int? = nil) -> some View {
        self
            .navigationBarBackButtonHidden(true)
            .toolbar { AppHeader(title: title, trailingBadgeCount: trailingBadgeCount) }
            .toolbarBackground(V2Theme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
    }
}
