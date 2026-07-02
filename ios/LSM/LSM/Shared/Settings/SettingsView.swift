import SwiftUI

/// Settings (spec §7.2) — a short list of icon rows, each pushing to its own
/// screen, matching Apple's own Settings app. Settings isn't a daily screen,
/// so scannability at a glance matters more than seeing every control at once.
struct SettingsView: View {
    @AppStorage(ManagerSettings.nameKey) private var managerName = ""
    @Environment(Entitlements.self) private var entitlements
    @Environment(EnabledLeagues.self) private var enabled
    @Environment(LocalizationManager.self) private var localization

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        ProfileSettingsView()
                    } label: {
                        SettingsRow(
                            systemName: "person.crop.circle.fill", color: .gray,
                            title: "Profile", value: managerName.isEmpty ? nil : managerName
                        )
                    }
                }

                Section {
                    NavigationLink {
                        SubscriptionSettingsView()
                    } label: {
                        SettingsRow(systemName: "star.fill", color: .orange, title: "Subscription", value: entitlements.tier.label)
                    }
                    NavigationLink {
                        LeagueSettingsView()
                    } label: {
                        SettingsRow(systemName: "trophy.fill", color: .green, title: "Leagues", value: "\(enabled.ids.count)/\(entitlements.leagueAllowance)")
                    }
                    NavigationLink {
                        BackupSettingsView()
                    } label: {
                        SettingsRow(systemName: "icloud.fill", color: .blue, title: "Backup & Cloud")
                    }
                    NavigationLink {
                        RosterSettingsView()
                    } label: {
                        SettingsRow(systemName: "person.2.fill", color: .purple, title: "Roster")
                    }
                }

                Section {
                    NavigationLink {
                        LanguageSettingsView()
                    } label: {
                        SettingsRow(systemName: "globe", color: .blue, title: "Language", value: localization.language.displayName)
                    }
                    NavigationLink {
                        AboutView()
                    } label: {
                        SettingsRow(systemName: "info.circle.fill", color: .gray, title: "About")
                    }
                }
            }
            .appBackground()
            .navigationTitle("Settings")
        }
    }
}
