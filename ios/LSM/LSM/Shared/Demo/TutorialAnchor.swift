import SwiftUI

// MARK: - Frame-reporting anchor (main screens)

/// Tags a real app control so TutorialManager knows its position. When the
/// tutorial's current step targets this anchor, a pulsing border appears around
/// the control and the dim overlay cuts a hole at its position.
extension View {
    func tutorialAnchor(id: String) -> some View {
        modifier(TutorialAnchorModifier(anchorId: id))
    }

    /// Lightweight highlight for controls inside sheets where frame-reporting
    /// isn't meaningful (sheets live in a separate UIWindow layer). Shows the
    /// pulsing border when the tutorial is active and `condition` is true.
    func tutorialHighlight(when condition: Bool) -> some View {
        overlay {
            if TutorialManager.shared.isActive && condition {
                PulsingBorder()
            }
        }
    }
}

struct TutorialAnchorModifier: ViewModifier {
    let anchorId: String

    private var isCurrentAnchor: Bool {
        TutorialManager.shared.isActive &&
        TutorialManager.shared.currentStep.anchorId == anchorId
    }

    func body(content: Content) -> some View {
        content
            .background {
                GeometryReader { geo in
                    let f = geo.frame(in: .named("tutorialRoot"))
                    Color.clear
                        .onAppear { TutorialManager.shared.setFrame(f, id: anchorId) }
                        .onChange(of: f) { _, newFrame in
                            TutorialManager.shared.setFrame(newFrame, id: anchorId)
                        }
                }
            }
            .overlay {
                if isCurrentAnchor { PulsingBorder() }
            }
    }
}

// MARK: - Sheet-level callout banner

/// Compact tutorial banner for sheet views (OpenRoundView, PicksEntryView,
/// ResultsEntryView). Since sheets already focus attention, we skip the dim
/// and just show a small guidance bar at the top.
struct TutorialSheetBanner: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "wand.and.rays")
                .foregroundStyle(.tint)
                .font(.subheadline)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.bold())
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.1))
    }
}

// MARK: - Pulsing border (internal)

struct PulsingBorder: View {
    @State private var pulse = false

    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(Color.yellow, lineWidth: pulse ? 2.5 : 1.5)
            .padding(-6)
            .scaleEffect(pulse ? 1.025 : 1.0)
            .opacity(pulse ? 1.0 : 0.55)
            .animation(
                .easeInOut(duration: 0.75).repeatForever(autoreverses: true),
                value: pulse
            )
            .onAppear { pulse = true }
            .allowsHitTesting(false)
    }
}
