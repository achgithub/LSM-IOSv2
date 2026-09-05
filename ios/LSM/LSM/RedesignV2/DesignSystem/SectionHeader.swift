import SwiftUI

/// Bold section heading with an optional secondary subtitle, used above a
/// group of cards instead of a List section header.
///
/// `title`/`subtitle` are `LocalizedStringKey`, not `String`, so a literal
/// at the call site goes through `Localizable.xcstrings` automatically. They
/// used to be `String`, which meant `Text(title)` hit SwiftUI's *verbatim*
/// initializer and every heading in V2 rendered English in all six
/// languages — silently, since a missing translation still compiles.
///
/// When the heading really is user data (a game or player name), use
/// `SectionHeader(verbatim:)`. A `String` will not bind to the localized
/// parameter, so the compiler forces that to be a deliberate choice rather
/// than something that slips through.
struct SectionHeader: View {
    private let title: Text
    private let subtitle: Text?

    init(title: LocalizedStringKey, subtitle: LocalizedStringKey? = nil) {
        self.title = Text(title)
        self.subtitle = subtitle.map { Text($0) }
    }

    /// For headings built from user-supplied text, which must never be
    /// looked up in the catalog.
    init(verbatim title: String, subtitle: String? = nil) {
        self.title = Text(verbatim: title)
        self.subtitle = subtitle.map { Text(verbatim: $0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            title
                .font(V2Theme.Typography.sectionHeading)
                .foregroundStyle(V2Theme.textPrimary)
            if let subtitle {
                subtitle
                    .font(V2Theme.Typography.metadata)
                    .foregroundStyle(V2Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
