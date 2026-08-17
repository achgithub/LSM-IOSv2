import SwiftUI
import Lottie

/// Small looping football animation used for V2 loading states. Colored at
/// export time (a fixed teal, `DribblingSoccer.json` is pre-baked) rather
/// than via Lottie's runtime `ColorValueProvider` — this file nests the man
/// silhouette two precomps deep, and a value provider only reached the
/// single-nested ball, leaving the man stuck at its original black
/// regardless of keypath wildcarding or rendering engine. Falls back to the
/// platform spinner under Reduce Motion.
struct V2LoadingIndicator: View {
    var size: CGFloat = 44

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            ProgressView()
                .frame(width: size, height: size)
        } else {
            LottieView(animation: .named("DribblingSoccer"))
                .playing(loopMode: .loop)
                .resizable()
                .frame(width: size, height: size)
        }
    }
}

/// Bottom-anchored loading badge shared by V2 screens — same animation +
/// label whether it's covering an empty first-load screen or floating over
/// already-loaded content during a refresh, so both cases read as one
/// consistent piece of UI rather than two different loading treatments.
struct V2LoadingBadge: View {
    let label: LocalizedStringKey

    var body: some View {
        HStack(spacing: 8) {
            V2LoadingIndicator(size: 28)
            Text(label)
                .font(V2Theme.Typography.metadata)
                .foregroundStyle(V2Theme.textSecondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(V2Theme.cardBackground, in: Capsule())
        .overlay(Capsule().strokeBorder(V2Theme.cardBorder))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
    }
}

private struct V2LoadingOverlayModifier: ViewModifier {
    let isLoading: Bool
    let label: LocalizedStringKey

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if isLoading {
                    V2LoadingBadge(label: label)
                        .padding(.bottom, 12)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: isLoading)
    }
}

extension View {
    /// Shows the small bottom-anchored loading badge while `isLoading` is
    /// true. Deliberately the same treatment for blank first-load and for
    /// refresh-over-existing-content — pilot screens use it for both so the
    /// two cases can be compared before deciding whether first-load should
    /// look different.
    func v2LoadingOverlay(_ isLoading: Bool, label: LocalizedStringKey) -> some View {
        modifier(V2LoadingOverlayModifier(isLoading: isLoading, label: label))
    }
}
