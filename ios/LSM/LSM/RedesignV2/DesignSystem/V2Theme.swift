import SwiftUI
import UIKit

/// Central design tokens for the V2 (card-based) redesign — every V2 screen
/// and component reads colors/spacing/type from here, never a literal value,
/// so the whole look can be swapped later by editing only this file.
///
/// Palette modeled on the reference mockup (lms-app-mockup.tsx): navy
/// background, flat panels with a faint border, teal-green as the
/// primary/positive accent, gold for attention/deadlines, red for danger/
/// elimination. Light-mode values are this app's own equivalent (the
/// reference is dark-only) — same accent hues, inverted neutrals.
///
/// Light/dark values are independent design choices, not a single palette
/// dimmed/brightened — adjust either side freely.
enum V2Theme {
    static let background = Color.v2(light: 0xF4F5F7, dark: 0x0B1220)
    /// Flat card/panel fill — paired with `cardBorder`'s stroke by default
    /// (see `Card`); `Card.floating` swaps both for `.v2FloatingCard()`'s
    /// own translucent fill/border pair instead.
    static let cardBackground = Color.v2(light: 0xFFFFFF, dark: 0x111A2B)
    /// Faint seam only needed on a plain-white panel in light mode; in dark
    /// mode it matches `cardBackground` so no seam shows, matching the
    /// reference's borderless panels.
    static let cardBorder = Color.v2(light: 0xE4E7EB, dark: 0x111A2B)
    /// Tinted background for a selected/highlighted row (the picked fixture
    /// in the reference) — pair with `accent` as the border.
    static let highlightBackground = Color.v2(light: 0xE8F5EF, dark: 0x152A22)
    /// Secondary panel fill for pills/strips/avatar badges (deadline strip).
    static let pillBackground = Color.v2(light: 0xEEF0F3, dark: 0x1E2A3A)

    /// Primary/positive accent — teal-green.
    static let accent = Color.v2(light: 0x2F9C74, dark: 0x3EB489)
    /// Text/icon color to place on top of a solid `accent` fill. Fixed (not
    /// theme-adaptive) — always dark navy, matching the reference's
    /// confirm-button and check-icon treatment regardless of appearance.
    static let accentOnAccent = Color(UIColor(v2Hex: 0x0B1220))
    /// Attention / due-soon — gold.
    static let warning = Color.v2(light: 0xB8860B, dark: 0xF2B705)
    /// Danger / eliminated / out — red.
    static let danger = Color.v2(light: 0xC72E3B, dark: 0xE63946)

    static let textPrimary = Color.v2(light: 0x121A22, dark: 0xF5F7FA)
    /// Darkened from the original 0x5C6B78 — over a floating card on a
    /// photo background (not just a flat surface), the lighter value read
    /// as too pale ("Due Fri 28 Aug", "Matchday 5", etc. were hard to read).
    static let textSecondary = Color.v2(light: 0x43566A, dark: 0x8B9AAE)
    static let textTertiary = Color.v2(light: 0x8B95A1, dark: 0x5C6B80)

    /// Per-mode identity — distinct color + font design for LMS/Predictor/
    /// Killer so their portal sections read apart at a glance. Colors are
    /// deliberately outside the status palette (accent/warning/danger) so a
    /// mode's own identity never gets confused with a submitted/alive/out cue.
    enum Mode {
        static let lms = Color.v2(light: 0x1D6FD1, dark: 0x4C9AFF)
        static let predictor = Color.v2(light: 0x4338CA, dark: 0x6366F1)
        static let killer = Color.v2(light: 0xB8311E, dark: 0xF2542D)

        static func color(for mode: GameMode) -> Color {
            switch mode {
            case .lms: return lms
            case .predictor: return predictor
            case .killer: return killer
            }
        }

        static func fontDesign(for mode: GameMode) -> Font.Design {
            switch mode {
            case .lms: return .rounded
            case .predictor: return .monospaced
            case .killer: return .serif
            }
        }

        static func icon(for mode: GameMode) -> String {
            switch mode {
            case .lms: return "shield.lefthalf.filled"
            case .predictor: return "chart.line.uptrend.xyaxis"
            case .killer: return "scope"
            }
        }

        static func displayName(for mode: GameMode) -> String {
            switch mode {
            case .lms: return "Last Man Standing"
            case .predictor: return "Predictor"
            case .killer: return "Killer"
            }
        }
    }

    /// Stable per-game color for contexts that mix rows from several games at
    /// once (the submission inbox) — distinct from `Mode.color`, which is
    /// shared by every game of the same mode and wouldn't tell two LMS games
    /// apart. `Game` has no color field of its own, so this hashes the
    /// game's cloud token into a fixed palette: same game always gets the
    /// same color, no data model change needed.
    enum GameIdentity {
        private static let palette: [Color] = [
            Color.v2(light: 0x1D6FD1, dark: 0x4C9AFF),
            Color.v2(light: 0xB8311E, dark: 0xF2542D),
            Color.v2(light: 0x4338CA, dark: 0x6366F1),
            Color.v2(light: 0x0F8B8D, dark: 0x2DD4BF),
            Color.v2(light: 0xB8860B, dark: 0xF2B705),
            Color.v2(light: 0xA6266E, dark: 0xEC4899),
            Color.v2(light: 0x5C7A29, dark: 0x84CC16),
            Color.v2(light: 0x6B4E9C, dark: 0xA78BFA),
        ]

        static func color(for gameToken: String) -> Color {
            // `String.hashValue` is randomized per process launch, so it
            // can't be used here — the same game would repaint a different
            // color every relaunch. FNV-1a over the UTF8 bytes is stable.
            var hash: UInt64 = 0xcbf29ce484222325
            for byte in gameToken.utf8 {
                hash ^= UInt64(byte)
                hash = hash &* 0x100000001b3
            }
            return palette[Int(hash % UInt64(palette.count))]
        }
    }

    enum Radius {
        static let card: CGFloat = 18
        static let row: CGFloat = 14
        static let pill: CGFloat = 12
        static let button: CGFloat = 14
    }

    enum Spacing {
        static let section: CGFloat = 20
        static let cardPadding: CGFloat = 18
        static let horizontal: CGFloat = 16

        /// Height for a screen embedded inline inside another's accordion
        /// panel (Leagues' Fixtures/Standings/Manage/Subscription, Players'
        /// Roster) — bounded by the device's screen height rather than a
        /// bare literal. A fixed `560` could exceed the viewport entirely on
        /// a small device once the ~260pt tile header above it is accounted
        /// for (see V2 audit 1.2); this also converges what used to be two
        /// independent copies of that same `560` literal, one each in
        /// `LeaguesPortalViewV2` and `PlayersViewV2`, into the one value
        /// both now read. Floors at 320 so the panel doesn't collapse to
        /// something unusably short either.
        static var inlinePanelHeight: CGFloat {
            min(560, max(320, UIScreen.main.bounds.height * 0.62))
        }
    }

    /// Tokens for the stadium-atmosphere chrome behind V2 scenes (see
    /// `V2StadiumBackground`). One shared daylight image is graded, not
    /// swapped, to produce the dark appearance — see `RedesignV2/POC/
    /// V2-THEME-HANDOFF.md` for the agreed direction this formalizes.
    enum Atmosphere {
        /// Image adjustments applied only in dark mode; light mode shows the
        /// source artwork unmodified (floodlights "off").
        static let darkSaturation: Double = 0.62
        static let darkContrast: Double = 1.10
        static let darkBrightness: Double = -0.26
        static let darkMultiplyGrade = Color.v2(light: 0xFFFFFF, dark: 0x071426)
        static let darkMultiplyOpacity: Double = 0.54

        /// Mild grading applied in light mode too (see `V2PhotoBackground`)
        /// — the raw interior photos (Trophy/Team/Data Room, Tactics
        /// Office) at full saturation/contrast competed with card content
        /// instead of reading as scenery. Kept small enough to preserve the
        /// bright sky/warm wood, not a grey wash.
        static let lightSaturation: Double = 0.94
        static let lightContrast: Double = 0.90

        /// Central readability scrim (see `.v2*Scene()`) — a soft, roughly
        /// elliptical wash behind the scrolling content column, strongest
        /// in the middle where cards/headings sit, fading out before the
        /// edges and before the bottom so the richer photo detail (and the
        /// pitch/floor) stays visible at the sides and bottom. Uses
        /// `V2Theme.background` (not a fixed white) so it's a light wash in
        /// light mode and a dark wash in dark mode — same adaptive
        /// approach as `V2FloatingHeader`'s scrim.
        static let contentScrimOpacity: Double = 0.26

        /// Floodlight housing/beam color — fixed blue-white, not mode-tinted,
        /// so the lamps read the same regardless of which screen/mode accent
        /// is passed to `V2StadiumBackground`.
        static let lampGlow = Color(UIColor(v2Hex: 0x3DA8FF))

        /// Legibility knob between the image and card content, read by every
        /// `.v2*Scene()` via `V2StadiumBackdrop`/`V2PhotoSceneModifier` — one
        /// global value, not a per-screen setting. Kept low; raise here (not
        /// per call site) only if content over the busier parts of the image
        /// (e.g. long standings lists) proves hard to read — see the
        /// handoff doc's "manageable risk, mitigate with translucency" call.
        static let contentOverlayOpacity: Double = 0.05
        /// Used instead of `contentOverlayOpacity` when Reduce Transparency
        /// is on — the image stays but content gets a solid-enough backing
        /// that translucency isn't relied on for legibility.
        static let reduceTransparencyOverlayOpacity: Double = 0.9

        /// Ambient particle field: kept deliberately sparse/slow — this is
        /// continuous background motion, not a one-off celebration effect
        /// (see `V2LoadingIndicator`/Lottie for those), so it needs to stay
        /// cheap to run behind every V2 screen.
        static let particleCount = 10
        static let particleRefreshInterval: Double = 1.0 / 12.0
    }

    enum Typography {
        static let pageTitle = Font.system(.title2, design: .rounded).weight(.bold)
        static let sectionHeading = Font.system(.headline, design: .rounded).weight(.bold)
        static let rowTitle = Font.system(.body).weight(.semibold)
        static let metadata = Font.system(.caption)
        /// Small uppercase-tracked label ("ROUND 14", "LEAGUE STANDINGS") —
        /// pair with `.textCase(.uppercase)` and `.tracking(1.1)`, matching
        /// `MicroLabel`'s own usage.
        static let microLabel = Font.system(.caption2).weight(.semibold)
    }
}

private extension Color {
    /// Dynamic color from separate light/dark "0xRRGGBB" values.
    static func v2(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(v2Hex: dark) : UIColor(v2Hex: light)
        })
    }
}

private extension UIColor {
    convenience init(v2Hex hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
