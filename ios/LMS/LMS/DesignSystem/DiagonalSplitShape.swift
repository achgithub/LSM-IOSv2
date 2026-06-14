import SwiftUI

/// A right-triangle that fills half of a square along the top-left → bottom-right
/// diagonal. Two of these (one inverted) form the §15 two-colour team tile.
struct DiagonalSplitShape: Shape {
    var invert: Bool = false

    func path(in rect: CGRect) -> Path {
        var path = Path()
        if invert {
            // Bottom-right triangle
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        } else {
            // Top-left triangle
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        }
        path.closeSubpath()
        return path
    }
}
