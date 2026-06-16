import Testing
import Foundation
@testable import LMS

/// Pins down which `String(localized:)` lever selects the in-app language table
/// from the app bundle (where the compiled .lproj live).
struct LocalizationLocaleTests {
    private func esBundle() throws -> Bundle {
        let appBundle = Bundle(for: Entitlements.self)
        let esPath = try #require(appBundle.path(forResource: "es", ofType: "lproj"))
        return try #require(Bundle(path: esPath))
    }

    @Test func subBundleStringLocalized() throws {
        // Does String(localized:bundle:) honor a language sub-bundle? (handles interpolation)
        #expect(String(localized: "Anonymous", bundle: try esBundle()) == "Anónimo")
        #expect(String(localized: "Round \(3)", bundle: try esBundle()) == "Ronda 3")
    }

    @Test func subBundleLegacyLookup() throws {
        #expect(try esBundle().localizedString(forKey: "Anonymous", value: nil, table: nil) == "Anónimo")
    }
}
