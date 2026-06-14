import SwiftUI

/// A club's bespoke two-colour visual identity (spec §15). Owned by the product —
/// no crest licensing. Bundled in team-signatures.json, keyed by abbreviation
/// which is joined to the provider's TLA at runtime.
struct TeamSignature: Decodable, Identifiable {
    let abbrev: String
    let name: String
    let primaryHex: String
    let secondaryHex: String

    var id: String { abbrev }
    var primaryColor: Color { Color(hex: primaryHex) }
    var secondaryColor: Color { Color(hex: secondaryHex) }

    /// White or dark label depending on the average luminance of the two halves.
    var labelColor: Color {
        let avg = (hexLuminance(primaryHex) + hexLuminance(secondaryHex)) / 2.0
        return avg > 0.6 ? .black : .white
    }
}

/// Registry of the bundled team signatures.
enum TeamSignatures {
    static let all: [TeamSignature] = load()

    private static let byAbbrev: [String: TeamSignature] =
        Dictionary(all.map { ($0.abbrev.uppercased(), $0) }, uniquingKeysWith: { first, _ in first })

    /// Look up by the provider's three-letter code (TLA), case-insensitive.
    static func lookup(tla: String?) -> TeamSignature? {
        guard let tla else { return nil }
        return byAbbrev[tla.uppercased()]
    }

    private static func load() -> [TeamSignature] {
        struct Wrapper: Decodable { let teams: [TeamSignature] }
        guard let url = Bundle.main.url(forResource: "team-signatures", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let wrapper = try? JSONDecoder().decode(Wrapper.self, from: data) else {
            return []
        }
        return wrapper.teams
    }
}
