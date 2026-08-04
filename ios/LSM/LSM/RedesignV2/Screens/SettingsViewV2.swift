import SwiftUI

/// Card restyle of `SettingsView`'s row list — pushed into an existing
/// NavigationStack (no `List`, no embedded NavigationStack), matching the
/// "restyle the list, not-yet-restyled detail stays v1" precedent set by
/// `PlayersViewV2`/`GamesPortalViewV2`. Every row still pushes the unchanged
/// v1 detail screen (Profile, Subscription, Leagues, Roster, Language,
/// About, Report a Bug) — none of those have been restyled yet.
struct SettingsViewV2: View {
    @AppStorage(ManagerSettings.nameKey) private var managerName = ""
    @Environment(Entitlements.self) private var entitlements
    @Environment(EnabledLeagues.self) private var enabled
    @Environment(LocalizationManager.self) private var localization

    var body: some View {
        ScrollView {
            LazyVStack(spacing: V2Theme.Spacing.section) {
                VStack(spacing: 10) {
                    NavigationLink {
                        ProfileSettingsView()
                    } label: {
                        MenuRow(systemImage: "person.crop.circle.fill", title: "Profile",
                                value: managerName.isEmpty ? nil : managerName)
                    }
                    .buttonStyle(.plain)
                    NavigationLink {
                        SubscriptionSettingsView()
                    } label: {
                        MenuRow(systemImage: "star.fill", title: "Subscription", value: entitlements.tier.label)
                    }
                    .buttonStyle(.plain)
                    NavigationLink {
                        LeagueSettingsView()
                    } label: {
                        MenuRow(systemImage: "trophy.fill", title: "Leagues",
                                value: "\(enabled.ids.count)/\(entitlements.leagueAllowance)")
                    }
                    .buttonStyle(.plain)
                    NavigationLink {
                        RosterSettingsView()
                    } label: {
                        MenuRow(systemImage: "person.2.fill", title: "Roster")
                    }
                    .buttonStyle(.plain)
                }

                VStack(spacing: 10) {
                    NavigationLink {
                        LanguageSettingsView()
                    } label: {
                        MenuRow(systemImage: "globe", title: "Language", value: localization.language.displayName)
                    }
                    .buttonStyle(.plain)
                    NavigationLink {
                        AboutView()
                    } label: {
                        MenuRow(systemImage: "info.circle.fill", title: "About")
                    }
                    .buttonStyle(.plain)
                    NavigationLink {
                        ReportBugView()
                    } label: {
                        MenuRow(systemImage: "ladybug.fill", title: "Report a Bug")
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, V2Theme.Spacing.horizontal)
            .padding(.vertical, V2Theme.Spacing.section)
        }
        .background(V2Theme.background.ignoresSafeArea())
        .v2Header("Settings")
    }
}
