import SwiftUI
import Lottie

/// Small looping football animation used for V2 loading states, recolored to
/// the design system's accent so it matches light/dark automatically. Falls
/// back to the platform spinner under Reduce Motion.
struct V2LoadingIndicator: View {
    var size: CGFloat = 44

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            ProgressView()
                .frame(width: size, height: size)
        } else {
            LottieView(animation: .named("DribblingSoccer"))
                .playing(loopMode: .loop)
                .resizable()
                .valueProvider(
                    ColorValueProvider(V2Theme.accent.resolvedLottieColor(scheme: colorScheme)),
                    for: AnimationKeypath(keypath: "**")
                )
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

private extension Color {
    /// Resolves a dynamic `Color` against an explicit color scheme (rather
    /// than the current UITraitCollection) so the Lottie recolor always
    /// matches the SwiftUI environment even if it differs from the system
    /// appearance (e.g. a forced `.preferredColorScheme`).
    func resolvedLottieColor(scheme: ColorScheme) -> LottieColor {
        let traits = UITraitCollection(userInterfaceStyle: scheme == .dark ? .dark : .light)
        let uiColor = UIColor(self).resolvedColor(with: traits)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        return LottieColor(r: Double(r), g: Double(g), b: Double(b), a: Double(a))
    }
}
