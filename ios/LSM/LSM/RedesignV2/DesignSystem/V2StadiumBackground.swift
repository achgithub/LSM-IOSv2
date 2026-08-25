import SwiftUI

/// Stadium-atmosphere chrome behind a V2 scene: one fixed daylight image
/// (`V2Stadium` in the asset catalog), graded into the dark appearance
/// rather than swapped, plus procedural floodlight glow in dark mode and a
/// sparse ambient particle field. Production version of
/// `RedesignV2/POC/V2ExperienceThemePOC.swift`'s `POCStadiumBackground` —
/// see `RedesignV2/POC/V2-THEME-HANDOFF.md` for the agreed direction.
///
/// Use via `.v2StadiumScene(accent:)` rather than directly — that also wires
/// up the legibility overlay content sits on top of.
struct V2StadiumBackground: View {
    var accent: Color = V2Theme.accent

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let stadium = Self.stadiumImage {
                    Image(uiImage: stadium)
                        .resizable()
                        // Fill + crop, not fit — a fit/letterbox left blank
                        // gaps (falling through to plain `V2Theme.background`)
                        // top and bottom whenever the device's aspect ratio
                        // didn't exactly match the artwork's. A full-bleed
                        // background needs to always cover the viewport;
                        // some crop varying by device is the accepted
                        // tradeoff, same as any hero background image.
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                        .saturation(colorScheme == .dark ? V2Theme.Atmosphere.darkSaturation : 1)
                        .contrast(colorScheme == .dark ? V2Theme.Atmosphere.darkContrast : 1)
                        .brightness(colorScheme == .dark ? V2Theme.Atmosphere.darkBrightness : 0)
                }

                if colorScheme == .dark {
                    V2Theme.Atmosphere.darkMultiplyGrade
                        .opacity(V2Theme.Atmosphere.darkMultiplyOpacity)
                        .blendMode(.multiply)
                    // Fill means the rendered image frame always equals
                    // proxy.size exactly (no letterbox), so lamp/beam
                    // positions can go straight back to plain proportions
                    // of the viewport instead of a computed fit-rect.
                    V2StadiumLighting(imageRect: CGRect(origin: .zero, size: proxy.size))
                }

                accent.opacity(colorScheme == .dark ? 0.08 : 0.03)
                    .blendMode(.plusLighter)

                if !reduceMotion {
                    V2StadiumParticles(accent: accent)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    /// Loaded once per process rather than on every render — the same
    /// artwork backs every V2 screen, so there's no reason to re-decode the
    /// PNG per scene appearance.
    private static let stadiumImage: UIImage? = UIImage(named: "V2Stadium")
}

/// Floodlight housings + beams, positioned as proportions of the viewport
/// (`imageRect` is always the full proxy size — see `.scaledToFill()` above).
private struct V2StadiumLighting: View {
    let imageRect: CGRect

    var body: some View {
        ZStack {
            ForEach(0..<9, id: \.self) { index in
                let progress = CGFloat(index) / 8
                let y = imageRect.minY + imageRect.height * (0.132 + progress * 0.142)
                let inset = imageRect.width * (0.018 + progress * 0.078)

                V2Floodlight(angle: -14)
                    .position(x: imageRect.minX + inset, y: y)
                V2Floodlight(angle: 14)
                    .position(x: imageRect.maxX - inset, y: y)
            }

            Canvas { context, _ in
                let topY = imageRect.minY + 120
                var leftBeam = Path()
                leftBeam.move(to: CGPoint(x: imageRect.minX, y: topY))
                leftBeam.addLine(to: CGPoint(x: imageRect.minX + imageRect.width * 0.47, y: imageRect.minY + imageRect.height * 0.72))
                leftBeam.addLine(to: CGPoint(x: imageRect.minX + imageRect.width * 0.28, y: imageRect.minY + imageRect.height * 0.72))
                leftBeam.closeSubpath()

                var rightBeam = Path()
                rightBeam.move(to: CGPoint(x: imageRect.maxX, y: topY))
                rightBeam.addLine(to: CGPoint(x: imageRect.minX + imageRect.width * 0.72, y: imageRect.minY + imageRect.height * 0.72))
                rightBeam.addLine(to: CGPoint(x: imageRect.minX + imageRect.width * 0.53, y: imageRect.minY + imageRect.height * 0.72))
                rightBeam.closeSubpath()

                context.fill(leftBeam, with: .linearGradient(
                    Gradient(colors: [V2Theme.Atmosphere.lampGlow.opacity(0.20), .clear]),
                    startPoint: CGPoint(x: imageRect.minX, y: topY),
                    endPoint: CGPoint(x: imageRect.minX + imageRect.width * 0.40, y: imageRect.minY + imageRect.height * 0.65)
                ))
                context.fill(rightBeam, with: .linearGradient(
                    Gradient(colors: [V2Theme.Atmosphere.lampGlow.opacity(0.20), .clear]),
                    startPoint: CGPoint(x: imageRect.maxX, y: topY),
                    endPoint: CGPoint(x: imageRect.minX + imageRect.width * 0.60, y: imageRect.minY + imageRect.height * 0.65)
                ))
            }
        }
        .blendMode(.screen)
    }
}

private struct V2Floodlight: View {
    let angle: Double

    var body: some View {
        ZStack {
            Circle()
                .fill(V2Theme.Atmosphere.lampGlow.opacity(0.42))
                .frame(width: 42, height: 42)
                .blur(radius: 11)
            Circle()
                .fill(Color.white.opacity(0.72))
                .frame(width: 22, height: 22)
                .blur(radius: 5)
            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .fill(Color.white)
                .frame(width: 9, height: 14)
                .overlay {
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .stroke(V2Theme.Atmosphere.lampGlow.opacity(0.9), lineWidth: 1)
                }
                .shadow(color: .white.opacity(0.95), radius: 5)
        }
        .rotationEffect(.degrees(angle))
    }
}

/// Sparse drifting particle field — deliberately low count/refresh rate
/// (`V2Theme.Atmosphere.particleCount`/`particleRefreshInterval`) since this
/// runs continuously behind every V2 screen, not just a celebratory moment.
private struct V2StadiumParticles: View {
    let accent: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: V2Theme.Atmosphere.particleRefreshInterval)) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                for index in 0..<V2Theme.Atmosphere.particleCount {
                    let lane = Double((index * 47) % 101) / 101
                    let travel = (phase * (7 + Double(index % 5)) + Double(index * 31))
                        .truncatingRemainder(dividingBy: size.height + 80)
                    let point = CGPoint(x: lane * size.width, y: travel - 40)
                    context.fill(
                        Path(ellipseIn: CGRect(x: point.x, y: point.y, width: 2, height: 2)),
                        with: .color(index.isMultiple(of: 4) ? accent.opacity(0.45) : .white.opacity(0.16))
                    )
                }
            }
        }
    }
}

/// Stadium image + legibility overlay. Must be composed as a `.background`
/// on the actual screen content inside a `NavigationStack`, not as a
/// sibling layer behind the `NavigationStack` itself — a `NavigationStack`
/// paints its own opaque background, so anything behind it (a ZStack
/// sibling, or a `.background` applied above it) never shows through,
/// regardless of `ignoresSafeArea`. Learned the hard way: see `.v2StadiumScene`.
struct V2StadiumBackdrop: View {
    var accent: Color = V2Theme.accent
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            V2Theme.background
            V2StadiumBackground(accent: accent)
            Color.white.opacity(
                reduceTransparency
                    ? V2Theme.Atmosphere.reduceTransparencyOverlayOpacity
                    : V2Theme.Atmosphere.contentOverlayOpacity
            )
        }
        // Without an explicit frame, a bare ZStack sizes itself from its
        // children's ideal size — and `V2StadiumBackground`'s internal
        // `GeometryReader` reports a near-zero ideal size when it isn't
        // already being fitted to something else's bounds (the case inside
        // `.background {}`, but not here, where this is a plain sibling of
        // `v2Content` in `V2RootView`). Forcing the full proposed size here
        // is what makes the image actually render either way.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }
}

private struct V2StadiumSceneModifier: ViewModifier {
    let accent: Color

    func body(content: Content) -> some View {
        content.background { V2StadiumBackdrop(accent: accent) }
    }
}

extension View {
    /// Wraps a V2 screen's content with the stadium background + legibility
    /// overlay. Drop-in replacement for `.background(V2Theme.background
    /// .ignoresSafeArea())` — content (cards, lists) stays exactly as it
    /// was; only the chrome behind it changes.
    func v2StadiumScene(accent: Color = V2Theme.accent) -> some View {
        modifier(V2StadiumSceneModifier(accent: accent))
    }
}
