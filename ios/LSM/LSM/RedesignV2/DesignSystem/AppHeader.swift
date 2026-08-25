import SwiftUI

/// Custom V2 header: circular translucent back button + centered bold title,
/// replacing the system nav bar look. Still a real NavigationStack toolbar —
/// `dismiss()` on a pushed screen, swipe-back gesture untouched — just
/// restyled, so no custom navigation stack to maintain.
struct AppHeader: ToolbarContent {
    /// Nil omits the centered title entirely (the immersive stadium root
    /// screen wants just the bell floating over the background, no "Home"
    /// text competing with the hero title already in its scrolling content).
    let title: String?
    /// False only for a screen that's the root of its `NavigationStack`
    /// (currently just `V2PreviewMenuView` as `V2RootView`'s root) — there's
    /// nothing to dismiss to there, so showing the back chevron would be a
    /// dead control instead of just omitting it.
    var showBack: Bool = true
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
        if showBack {
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
        }
        if let title {
            ToolbarItem(placement: .principal) {
                Text(title)
                    .font(V2Theme.Typography.pageTitle)
                    .foregroundStyle(V2Theme.textPrimary)
            }
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
    ///
    /// `transparentChrome` leaves the nav bar background unpainted (system
    /// default translucent material) instead of the opaque `V2Theme
    /// .background` fill — for the stadium root screen, where an opaque
    /// strip across the safe area would cut the image off instead of
    /// letting it read as one continuous scene behind the status bar, the
    /// way the POC's reference does.
    func v2Header(_ title: String?, showBack: Bool = true, transparentChrome: Bool = false, trailingBadgeCount: Int? = nil) -> some View {
        self
            .navigationBarBackButtonHidden(true)
            // Without this, the nav bar reserves large-title height even
            // though AppHeader supplies its own title text — left the gap
            // between the header and the first card oversized.
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { AppHeader(title: title, showBack: showBack, trailingBadgeCount: trailingBadgeCount) }
            .toolbarBackground(V2Theme.background, for: .navigationBar)
            .toolbarBackground(transparentChrome ? .hidden : .visible, for: .navigationBar)
    }
}
