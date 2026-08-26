import SwiftUI

/// Post-push feedback card, shared by every screen that offers a PUSH tile
/// — currently just `GamesPortalViewV2` (see that screen's doc comment on
/// why Home no longer has its own). Reads `coordinator.showSummary`/
/// `lastPushResult` directly rather than taking a `Bool` binding, so every
/// call site shows identical feedback with no risk of one forgetting to
/// wire it up the way Home's tile once did (see V2 audit 1.1).
private struct V2PushSummaryModifier: ViewModifier {
    let coordinator: PushCoordinator

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if coordinator.showSummary, let result = coordinator.lastPushResult {
                Card(floating: true) {
                    HStack(spacing: 10) {
                        Image(systemName: result.errors.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(result.errors.isEmpty ? V2Theme.accent : V2Theme.warning)
                        Text(result.summaryText)
                            .font(V2Theme.Typography.metadata)
                            .foregroundStyle(V2Theme.textPrimary)
                    }
                }
                .padding(.horizontal, V2Theme.Spacing.horizontal)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut, value: coordinator.showSummary)
    }
}

extension View {
    /// Shows a brief confirmation card at the top of the screen after
    /// `coordinator.push(...)` finishes.
    func v2PushSummary(_ coordinator: PushCoordinator) -> some View {
        modifier(V2PushSummaryModifier(coordinator: coordinator))
    }
}
