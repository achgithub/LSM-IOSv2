import SwiftUI

/// Generic day/night photo chrome: two real photos, same geometry,
/// cross-faded by appearance rather than one image graded into the other
/// like `V2StadiumBackground` — used where the night shot already has its
/// practical lights switched on baked in, so there's no procedural lighting
/// layer to add. Backs both `.v2TeamRoomScene()` (Players/roster) and
/// `.v2TrophyRoomScene()` (Games) — see `RedesignV2/POC/V2-THEME-HANDOFF.md`.
///
/// Must be composed as a `.background` on the screen's own content inside
/// its `NavigationStack`, not a sibling behind it — a `NavigationStack`
/// paints its own opaque background, so anything behind it never shows
/// through regardless of `ignoresSafeArea` (see `V2StadiumBackdrop`'s doc
/// comment, where this was learned the hard way).
struct V2PhotoBackground: View {
    let dayImageName: String
    let nightImageName: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let day = UIImage(named: dayImageName) {
                    Image(uiImage: day)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                        // Mild grading even in light mode — the raw photo
                        // at full saturation/contrast competed with card
                        // content instead of reading as scenery. Small
                        // enough to keep the bright sky/warm wood, not a
                        // grey wash.
                        .saturation(V2Theme.Atmosphere.lightSaturation)
                        .contrast(V2Theme.Atmosphere.lightContrast)
                        .opacity(colorScheme == .dark ? 0 : 1)
                }
                if let night = UIImage(named: nightImageName) {
                    Image(uiImage: night)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                        .opacity(colorScheme == .dark ? 1 : 0)
                }
            }
            .animation(.easeInOut(duration: 0.35), value: colorScheme)
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

private struct V2PhotoSceneModifier: ViewModifier {
    let dayImageName: String
    let nightImageName: String
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    V2Theme.background
                    V2PhotoBackground(dayImageName: dayImageName, nightImageName: nightImageName)
                    if reduceTransparency {
                        Color.white.opacity(V2Theme.Atmosphere.reduceTransparencyOverlayOpacity)
                    } else {
                        // Targeted, not a flat wash over the whole image —
                        // strongest through the middle content column,
                        // fading out toward the edges (keeps the richer
                        // photo detail at the sides) and before the very
                        // bottom (keeps the floor/pitch visible).
                        EllipticalGradient(
                            colors: [
                                V2Theme.background.opacity(V2Theme.Atmosphere.contentScrimOpacity),
                                V2Theme.background.opacity(V2Theme.Atmosphere.contentScrimOpacity * 0.4),
                                .clear,
                            ],
                            center: .center,
                            startRadiusFraction: 0,
                            endRadiusFraction: 0.75
                        )
                        .padding(.bottom, 260)
                        .allowsHitTesting(false)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
            }
    }
}

extension View {
    /// Drop-in replacement for `.background(V2Theme.background
    /// .ignoresSafeArea())` on the Players/roster screens.
    func v2TeamRoomScene() -> some View {
        modifier(V2PhotoSceneModifier(dayImageName: "V2TeamRoomDay", nightImageName: "V2TeamRoomNight"))
    }

    /// Drop-in replacement for `.background(V2Theme.background
    /// .ignoresSafeArea())` on the Games screens.
    func v2TrophyRoomScene() -> some View {
        modifier(V2PhotoSceneModifier(dayImageName: "V2TrophyRoomDay", nightImageName: "V2TrophyRoomNight"))
    }

    /// Drop-in replacement for `.background(V2Theme.background
    /// .ignoresSafeArea())` on the Leagues/fixtures screens.
    func v2DataRoomScene() -> some View {
        modifier(V2PhotoSceneModifier(dayImageName: "V2DataRoomDay", nightImageName: "V2DataRoomNight"))
    }

    /// Drop-in replacement for `.background(V2Theme.background
    /// .ignoresSafeArea())` on Settings.
    func v2TacticsOfficeScene() -> some View {
        modifier(V2PhotoSceneModifier(dayImageName: "V2TacticsOfficeDay", nightImageName: "V2TacticsOfficeNight"))
    }

    /// Calm, low-detail per-mode backgrounds — a heavily blurred, mode-
    /// tinted location rather than the fuller browsing-screen scenes above,
    /// so the photo reads as quiet texture behind the content instead of
    /// competing with it. Originally just the busy form/entry screens
    /// (picks, predictions, results, round setup); now every single-mode V2
    /// screen uses its mode's scene here rather than the generic
    /// `v2TrophyRoomScene()` (standings/lives, tie resolution, declare
    /// winners, add players — see V2 audit 4.3), so "form" undersells what
    /// this now covers, but the three functions keep their names rather
    /// than force a rename mid-fix. Geometry-matched day/night pairs, same
    /// as the other scenes.
    func v2LMSFormScene() -> some View {
        modifier(V2PhotoSceneModifier(dayImageName: "V2LMSTunnelDay", nightImageName: "V2LMSTunnelNight"))
    }

    func v2PredictorFormScene() -> some View {
        modifier(V2PhotoSceneModifier(dayImageName: "V2PredictorDeskDay", nightImageName: "V2PredictorDeskNight"))
    }

    func v2KillerFormScene() -> some View {
        modifier(V2PhotoSceneModifier(dayImageName: "V2KillerDugoutDay", nightImageName: "V2KillerDugoutNight"))
    }
}
