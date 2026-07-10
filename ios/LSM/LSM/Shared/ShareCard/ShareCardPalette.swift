import SwiftUI

/// Colour set for a game-mode share card. Only bg, headerBar, and accent differ
/// between modes; positive/negative/text are universal.
struct ShareCardPalette {
    let bg: Color
    let headerBar: Color
    let accent: Color
    let positive: Color
    let negative: Color
    let textPrimary: Color
    let textSecondary: Color

    /// Dark forest + gold — Last Man Standing.
    static let lms = ShareCardPalette(
        bg: Color(hex: "0F1A14"),
        headerBar: Color(hex: "1A2E1E"),
        accent: Color(hex: "F0C030"),
        positive: Color(hex: "22C55E"),
        negative: Color(hex: "EF4444"),
        textPrimary: Color(hex: "F5F5F5"),
        textSecondary: Color(hex: "9CA3AF")
    )

    /// Dark navy + sky blue — Predictor.
    static let predictor = ShareCardPalette(
        bg: Color(hex: "0D1525"),
        headerBar: Color(hex: "162040"),
        accent: Color(hex: "38BDF8"),
        positive: Color(hex: "22C55E"),
        negative: Color(hex: "EF4444"),
        textPrimary: Color(hex: "F5F5F5"),
        textSecondary: Color(hex: "9CA3AF")
    )

    /// Near-black + crimson — Killer.
    static let killer = ShareCardPalette(
        bg: Color(hex: "170D0D"),
        headerBar: Color(hex: "2E1616"),
        accent: Color(hex: "F03030"),
        positive: Color(hex: "22C55E"),
        negative: Color(hex: "EF4444"),
        textPrimary: Color(hex: "F5F5F5"),
        textSecondary: Color(hex: "9CA3AF")
    )
}
