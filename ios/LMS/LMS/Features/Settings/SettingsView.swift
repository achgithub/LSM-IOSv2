import SwiftUI

/// Settings shell (spec §7.2). Subscription management, restore purchases, and
/// import-players-outside-creation arrive with the RevenueCat / import phases.
struct SettingsView: View {
    private let config = LeagueConfig.shared
    @AppStorage(ManagerSettings.nameKey) private var managerName = ""
    @Environment(Entitlements.self) private var entitlements

    private var tierBinding: Binding<Tier> {
        Binding(get: { entitlements.tier }, set: { entitlements.setDevTier($0) })
    }

    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("You") {
                    TextField("Your name", text: $managerName)
                        .textInputAutocapitalization(.words)
                    Text("You're added to games you create, and your pick is always shown on shared summary cards.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Subscription") {
                    LabeledContent("Plan", value: entitlements.tier.label)
                    Text(entitlements.tier.detail)
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Restore Purchases") {
                        Task { await PurchaseService.shared.restore() }
                    }
                }

                Section("Developer (testing)") {
                    Picker("Simulate tier", selection: tierBinding) {
                        ForEach(Tier.allCases) { Text($0.label).tag($0) }
                    }
                    Text("Flips ad-on / ad-off without a purchase. Free shows ads; No Ads / Pro hide them.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("League") {
                    LabeledContent("League", value: config.leagueName)
                    LabeledContent("Season", value: config.season)
                }
                Section("About") {
                    LabeledContent("App", value: config.appName)
                    LabeledContent("Version", value: version)
                    LabeledContent("Backend", value: config.workerBaseURL)
                }
            }
            .navigationTitle("Settings")
        }
    }
}
