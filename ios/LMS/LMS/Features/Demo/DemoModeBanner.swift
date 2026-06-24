import SwiftUI

/// The persistent Demo Mode control surface, shown above the tab bar while the
/// walkthrough runs. Explains the current step and offers the three controls the
/// brief calls for: advance (Next step / Keep exploring), Exit demo, and Clear
/// demo data. Reads everything from `DemoWalkthroughManager.shared`.
struct DemoModeBanner: View {
    @Environment(\.modelContext) private var context
    @Bindable var manager: DemoWalkthroughManager

    private var step: DemoStep { manager.currentStep }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Always-on "you're in the demo" line.
            HStack(spacing: 6) {
                Image(systemName: "wand.and.stars")
                Text(step.bannerText)
                    .font(.caption.weight(.semibold))
                Spacer()
            }
            .foregroundStyle(.white.opacity(0.95))

            // Current step explainer.
            VStack(alignment: .leading, spacing: 3) {
                Text(step.title)
                    .font(.subheadline.bold())
                Text(step.detail)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(.white)

            // Primary advance, then the two management controls.
            Button {
                manager.advance(context: context)
            } label: {
                HStack {
                    Text(step.primaryButtonTitle)
                    Spacer()
                    Image(systemName: step.isFinal ? "checkmark" : "arrow.right")
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.white)
            .foregroundStyle(Color.accentColor)
            .controlSize(.large)

            HStack(spacing: 12) {
                Button(role: .destructive) {
                    manager.clearAndRestart(context: context)
                } label: {
                    Label("Clear demo data", systemImage: "arrow.counterclockwise")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.white)

                Button {
                    manager.exit(context: context)
                } label: {
                    Label("Exit demo", systemImage: "xmark")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.white)
            }
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [Color.accentColor, Color.accentColor.opacity(0.85)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.2), radius: 8, y: 2)
        .padding(.horizontal, 10)
        .padding(.bottom, 4)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
