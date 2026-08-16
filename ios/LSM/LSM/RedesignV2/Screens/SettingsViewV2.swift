import SwiftUI

/// Card restyle of `SettingsView`'s row list — pushed into an existing
/// NavigationStack (no `List`, no embedded NavigationStack). Every row now
/// pushes its own restyled V2 detail screen (see `ProfileSettingsViewV2`
/// etc.) — the v1 originals are untouched, reachable only from v1's own
/// `SettingsView`.
struct SettingsViewV2: View {
    @AppStorage(ManagerSettings.nameKey) private var managerName = ""
    @AppStorage(AccountSettings.linkedEmailKey) private var linkedAccountEmail = ""
    @Environment(Entitlements.self) private var entitlements
    @Environment(EnabledLeagues.self) private var enabled
    @Environment(LocalizationManager.self) private var localization

    var body: some View {
        ScrollView {
            LazyVStack(spacing: V2Theme.Spacing.section) {
                VStack(spacing: 10) {
                    NavigationLink {
                        ProfileSettingsViewV2()
                    } label: {
                        MenuRow(systemImage: "person.crop.circle.fill", title: "Profile",
                                value: managerName.isEmpty ? nil : managerName)
                    }
                    .buttonStyle(.plain)
                    NavigationLink {
                        SubscriptionSettingsViewV2()
                    } label: {
                        MenuRow(systemImage: "star.fill", title: "Subscription", value: entitlements.tier.label)
                    }
                    .buttonStyle(.plain)
                    NavigationLink {
                        LeagueSettingsViewV2()
                    } label: {
                        MenuRow(systemImage: "trophy.fill", title: "Leagues",
                                value: "\(enabled.ids.count)/\(entitlements.leagueAllowance)")
                    }
                    .buttonStyle(.plain)
                    NavigationLink {
                        RosterSettingsViewV2()
                    } label: {
                        MenuRow(systemImage: "person.2.fill", title: "Roster")
                    }
                    .buttonStyle(.plain)
                    if entitlements.canUseCloud {
                        NavigationLink {
                            AccountSettingsViewV2()
                        } label: {
                            MenuRow(systemImage: "envelope.badge.shield.half.filled", title: "Account",
                                    value: linkedAccountEmail.isEmpty ? nil : linkedAccountEmail)
                        }
                        .buttonStyle(.plain)
                        NavigationLink {
                            GameSyncPickerViewV2()
                        } label: {
                            MenuRow(systemImage: "arrow.triangle.2.circlepath", title: "Sync Games")
                        }
                        .buttonStyle(.plain)
                    }
                }

                VStack(spacing: 10) {
                    NavigationLink {
                        LanguageSettingsViewV2()
                    } label: {
                        MenuRow(systemImage: "globe", title: "Language", value: localization.language.displayName)
                    }
                    .buttonStyle(.plain)
                    NavigationLink {
                        AboutViewV2()
                    } label: {
                        MenuRow(systemImage: "info.circle.fill", title: "About")
                    }
                    .buttonStyle(.plain)
                    NavigationLink {
                        ReportBugViewV2()
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
