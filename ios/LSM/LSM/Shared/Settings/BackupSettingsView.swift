import SwiftUI

/// Standalone screen wrapping `CloudBackupSection`, pushed from the
/// top-level Settings list instead of shown inline.
struct BackupSettingsView: View {
    var body: some View {
        List {
            CloudBackupSection()
        }
        .appBackground()
        .navigationTitle("Backup & Cloud")
        .navigationBarTitleDisplayMode(.inline)
    }
}
