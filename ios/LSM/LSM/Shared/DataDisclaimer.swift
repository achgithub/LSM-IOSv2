import SwiftUI

/// Single source for the "not affiliated" disclaimer shown under football
/// data (Matches/Standings/Results/Update-football-data footers) — kept in
/// one place rather than the same string duplicated per screen, which had
/// drifted to slightly different lengths in different spots. Shortened from
/// the original wording to the legally-relevant clause only, dropping the
/// "independent tool" explainer sentence.
///
/// `LocalizedStringKey`, not `String` — `Text(_:)` only picks the
/// auto-localized overload for a `LocalizedStringKey`; a plain `String`
/// argument renders verbatim with no String Catalog lookup.
enum DataDisclaimer {
    static let text: LocalizedStringKey = "Not affiliated with, licensed by or endorsed by any football club, league or federation."
}
