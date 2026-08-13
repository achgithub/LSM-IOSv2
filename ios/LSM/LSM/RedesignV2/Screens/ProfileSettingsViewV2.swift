import SwiftUI

/// Card restyle of `ProfileSettingsView` — same single field, same behavior.
struct ProfileSettingsViewV2: View {
    @AppStorage(ManagerSettings.nameKey) private var managerName = ""

    var body: some View {
        ScrollView {
            LazyVStack(spacing: V2Theme.Spacing.section) {
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "Your Name")
                        TextField("Your name", text: $managerName)
                            .textInputAutocapitalization(.words)
                            .padding(12)
                            .background(V2Theme.pillBackground, in: RoundedRectangle(cornerRadius: V2Theme.Radius.row, style: .continuous))
                        Text("You're added to games you create, and your pick is always shown on shared summary cards.")
                            .font(.caption)
                            .foregroundStyle(V2Theme.textSecondary)
                    }
                }
            }
            .padding(.horizontal, V2Theme.Spacing.horizontal)
            .padding(.vertical, V2Theme.Spacing.section)
        }
        .background(V2Theme.background.ignoresSafeArea())
        .v2Header("Profile")
    }
}
