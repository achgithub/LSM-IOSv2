import SwiftUI

/// App display language. Team, player and league names always come from the
/// league data itself, regardless of this setting.
struct LanguageSettingsView: View {
    @Environment(LocalizationManager.self) private var localization

    private var languageBinding: Binding<AppLanguage> {
        Binding(get: { localization.language }, set: { localization.select($0) })
    }

    var body: some View {
        List {
            Section {
                Picker("Language", selection: languageBinding) {
                    ForEach(AppLanguage.allCases) { language in
                        // Endonym (e.g. "Deutsch") — fixed, never translated.
                        Text(language.displayName).tag(language)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Choose the app's language. Team, player and league names always come from the league data.")
                    // Deliberately English-only (verbatim) so the disclaimer
                    // reads the same in every language.
                    Text(verbatim: "Translations are AI-assisted — please report any errors.")
                }
            }
        }
        .appBackground()
        .navigationTitle("Language")
        .navigationBarTitleDisplayMode(.inline)
    }
}
