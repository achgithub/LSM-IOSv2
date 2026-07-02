import SwiftUI

/// The manager's own display name — used when they're added to games they
/// create, and shown on shared summary cards.
struct ProfileSettingsView: View {
    @AppStorage(ManagerSettings.nameKey) private var managerName = ""

    var body: some View {
        List {
            Section {
                TextField("Your name", text: $managerName)
                    .textInputAutocapitalization(.words)
            } footer: {
                Text("You're added to games you create, and your pick is always shown on shared summary cards.")
            }
        }
        .appBackground()
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
    }
}
