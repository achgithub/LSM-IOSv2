import SwiftUI

/// Custom V2 header: circular translucent back button + centered bold title,
/// replacing the system nav bar look. Still a real NavigationStack toolbar —
/// `dismiss()` on a pushed screen, swipe-back gesture untouched — just
/// restyled, so no custom navigation stack to maintain.
struct AppHeader: ToolbarContent {
    let title: String
    /// Submission-inbox bell — shown whenever the caller opts in (Home/Games
    /// pass a count; other screens leave this nil and get no bell at all).
    /// Always visible once opted in, regardless of the count — not gated on
    /// > 0 — so the queue stays reachable rather than the bell vanishing
    /// whenever it happens to read 0 pending. Backed by `SubmissionBadgeStore`;
    /// tapping it pushes the unfiltered `SubmissionInboxViewV2` (all games,
    /// color-coded). The small numeric badge overlay only renders when count
    /// > 0.
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
        if let trailingBadgeCount {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    SubmissionInboxViewV2()
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "bell.fill")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(V2Theme.textPrimary)
                            .frame(width: 36, height: 36)
                            .background(V2Theme.cardBackground, in: Circle())
                        if trailingBadgeCount > 0 {
                            Text("\(trailingBadgeCount)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(4)
                                .background(V2Theme.danger, in: Circle())
                                .offset(x: 6, y: -6)
                        }
                    }
                }
                .accessibilityLabel(
                    trailingBadgeCount > 0
                        ? "Submission queue: \(trailingBadgeCount) pending"
                        : "Submission queue"
                )
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
            // Without this, the nav bar reserves large-title height even
            // though AppHeader supplies its own title text — left the gap
            // between the header and the first card oversized.
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { AppHeader(title: title, trailingBadgeCount: trailingBadgeCount) }
            .toolbarBackground(V2Theme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
    }
}
