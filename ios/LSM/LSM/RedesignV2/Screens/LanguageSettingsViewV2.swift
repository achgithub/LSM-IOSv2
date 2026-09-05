import SwiftUI

/// Card restyle of `LanguageSettingsView` — `SelectablePill` grid instead of
/// a native `Picker`, matching the pill pattern used elsewhere in V2
/// (Fixtures' league filter, Standings' league switcher).
struct LanguageSettingsViewV2: View {
    @Environment(LocalizationManager.self) private var localization

    var body: some View {
        ScrollView {
            LazyVStack(spacing: V2Theme.Spacing.section) {
                Card(floating: true) {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeader(title: "Language")
                        FlowPillGrid(items: AppLanguage.allCases) { language in
                            SelectablePill(verbatim: language.displayName, isSelected: language == localization.language) {
                                localization.select(language)
                            }
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Choose the app's language. Team, player and league names always come from the league data.")
                            Text(verbatim: "Translations are AI-assisted — please report any errors.")
                        }
                        .font(.caption)
                        .foregroundStyle(V2Theme.textSecondary)
                    }
                }
            }
            .padding(.horizontal, V2Theme.Spacing.horizontal)
            .padding(.vertical, V2Theme.Spacing.section)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .v2TacticsOfficeScene()
        .v2FloatingHeader("Language")
    }
}

/// Wraps pills onto multiple lines instead of one scrolling row — languages
/// (unlike league filters elsewhere in V2) are a fixed, browsable set worth
/// seeing all at once.
struct FlowPillGrid<Item: Identifiable, Content: View>: View {
    let items: [Item]
    @ViewBuilder let content: (Item) -> Content

    var body: some View {
        // Simple wrap layout: SwiftUI has no built-in flow layout pre-iOS 16
        // `Layout`, but a plain wrapping HStack-in-ScrollView reads oddly for
        // a short fixed list — a basic flexible grid is clearer here.
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(items) { item in
                content(item)
            }
        }
    }
}
