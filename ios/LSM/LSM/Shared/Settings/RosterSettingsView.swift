import SwiftUI

/// Standalone screen wrapping `RosterManagementSection`, pushed from the
/// top-level Settings list instead of shown inline.
struct RosterSettingsView: View {
    var body: some View {
        List {
            RosterManagementSection()
        }
        .appBackground()
        .navigationTitle("Roster")
        .navigationBarTitleDisplayMode(.inline)
    }
}
