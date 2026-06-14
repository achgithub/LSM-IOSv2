import SwiftUI

enum TileSize {
    case small   // 24pt — standings, score cards
    case medium  // 40pt — player rows, summaries
    case large   // 64pt — picks entry selector

    var points: CGFloat {
        switch self {
        case .small: return 24
        case .medium: return 40
        case .large: return 64
        }
    }
    var fontSize: CGFloat {
        switch self {
        case .small: return 9
        case .medium: return 14
        case .large: return 22
        }
    }
    var cornerRadius: CGFloat {
        switch self {
        case .small: return 5
        case .medium: return 8
        case .large: return 12
        }
    }
}

/// The §15 diagonal two-colour club tile. Falls back to a neutral grey tile with
/// the abbreviation when no signature matches (e.g. a club not yet in the file).
struct TeamTile: View {
    let abbrev: String
    let signature: TeamSignature?
    let size: TileSize

    init(tla: String?, fallbackAbbrev: String? = nil, size: TileSize = .medium) {
        let sig = TeamSignatures.lookup(tla: tla)
        self.signature = sig
        self.abbrev = (sig?.abbrev ?? tla ?? fallbackAbbrev ?? "?").uppercased()
        self.size = size
    }

    var body: some View {
        ZStack {
            if let signature {
                DiagonalSplitShape().fill(signature.primaryColor)
                DiagonalSplitShape(invert: true).fill(signature.secondaryColor)
                Text(abbrev)
                    .font(.system(size: size.fontSize, weight: .bold, design: .rounded))
                    .foregroundStyle(signature.labelColor)
            } else {
                Rectangle().fill(Color.gray.opacity(0.4))
                Text(abbrev)
                    .font(.system(size: size.fontSize, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size.points, height: size.points)
        .clipShape(RoundedRectangle(cornerRadius: size.cornerRadius))
    }
}
