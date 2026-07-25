import SwiftUI
import UIKit

/// Central design tokens for the V2 (card-based) redesign — every V2 screen
/// and component reads colors/spacing/type from here, never a literal value,
/// so the whole look can be swapped later by editing only this file.
///
/// Palette modeled on the reference mockup (lms-app-mockup.tsx): navy
/// background, flat panels with no border by default, teal-green as the
/// primary/positive accent, gold for attention/deadlines, red for danger/
/// elimination. Light-mode values are this app's own equivalent (the
/// reference is dark-only) — same accent hues, inverted neutrals.
///
/// Light/dark values are independent design choices, not a single palette
/// dimmed/brightened — adjust either side freely.
enum V2Theme {
    static let background = Color.v2(light: 0xF4F5F7, dark: 0x0B1220)
    /// Flat card/panel fill — no border by default (see `Card`).
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
    static let textSecondary = Color.v2(light: 0x5C6B78, dark: 0x8B9AAE)
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
    }

    enum Typography {
        static let pageTitle = Font.system(.title2, design: .rounded).weight(.bold)
        static let sectionHeading = Font.system(.headline, design: .rounded).weight(.bold)
        static let rowTitle = Font.system(.body).weight(.semibold)
        static let metadata = Font.system(.caption)
        /// Small uppercase-tracked label ("ROUND 14", "LEAGUE STANDINGS") —
        /// pair with `.textCase(.uppercase)` and `.tracking(1.2)`.
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
