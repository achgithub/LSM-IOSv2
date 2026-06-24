import SwiftUI

extension Color {
    /// Create a Color from a "#RRGGBB" hex string.
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# ")).uppercased()
        var rgb: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&rgb)
        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1.0)
    }
}

/// Relative luminance (sRGB approximation) of a "#RRGGBB" hex, 0…1.
/// Used to pick a contrasting label colour on team tiles.
func hexLuminance(_ hex: String) -> Double {
    let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
    var rgb: UInt64 = 0
    Scanner(string: cleaned).scanHexInt64(&rgb)
    let r = Double((rgb & 0xFF0000) >> 16) / 255.0
    let g = Double((rgb & 0x00FF00) >> 8) / 255.0
    let b = Double(rgb & 0x0000FF) / 255.0
    return 0.2126 * r + 0.7152 * g + 0.0722 * b
}
