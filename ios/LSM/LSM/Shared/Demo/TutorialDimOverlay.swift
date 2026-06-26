import SwiftUI

/// Full-screen dim with a cutout hole at the highlighted control's position,
/// plus a floating callout card at the bottom. Laid over the tutorial's
/// NavigationStack; passes taps through to the highlighted control.
struct TutorialDimOverlay: View {
    let onNext: () -> Void
    let onSkip: () -> Void
    let onExit: () -> Void

    private var step: TutorialStep { TutorialManager.shared.currentStep }
    private var frame: CGRect? { TutorialManager.shared.activeFrame }

    var body: some View {
        ZStack(alignment: .bottom) {
            dimLayer
            calloutCard
                .padding(.horizontal)
                .padding(.bottom, 16)
        }
        .ignoresSafeArea()
        .animation(.spring(duration: 0.35), value: step)
    }

    // MARK: - Dim layer

    @ViewBuilder
    private var dimLayer: some View {
        if let f = frame {
            let padded = f.insetBy(dx: -14, dy: -10)
            DimShape(highlightRect: padded)
                .fill(Color.black.opacity(0.58), style: FillStyle(eoFill: true))
                .ignoresSafeArea()
                .allowsHitTesting(false)
        } else {
            Color.black.opacity(0.58)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }

    // MARK: - Callout card

    private var calloutCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(step.title)
                        .font(.headline)
                    Text(step.detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button(action: onExit) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 10) {
                if !step.requiresManualAdvance {
                    Button(step.skipButtonTitle, action: onSkip)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                Spacer()
                Button(action: onNext) {
                    Text(step.nextButtonTitle)
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.28), radius: 16, y: 6)
    }
}

// MARK: - Cutout shape

/// Fills `rect` with a rounded hole — the outer rectangle minus the inner
/// cutout, using the even-odd fill rule so the cutout is transparent.
private struct DimShape: Shape {
    var highlightRect: CGRect

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get {
            AnimatablePair(
                AnimatablePair(highlightRect.minX, highlightRect.minY),
                AnimatablePair(highlightRect.width, highlightRect.height)
            )
        }
        set {
            highlightRect = CGRect(
                x: newValue.first.first,
                y: newValue.first.second,
                width: newValue.second.first,
                height: newValue.second.second
            )
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect)
        path.addRoundedRect(in: highlightRect, cornerSize: CGSize(width: 14, height: 14))
        return path
    }
}
