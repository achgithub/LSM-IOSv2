import SwiftUI

/// Home's HELP tile destination — absorbed the old dedicated Settings
/// screen entirely (Subscription moved to `FootballDataViewV2`, Roster moved
/// to `PlayersViewV2` — see those files) rather than keeping a separate
/// Settings section, per the 2026-08-25 restructure. What's left (Profile,
/// Language, About, Report a Bug) plus the "New design" v1 fallback toggle
/// didn't have anywhere more specific to live, so this is the catch-all.
/// Still named `SettingsViewV2` as a file/struct — only its role and header
/// title changed — to avoid an unrelated rename churning the diff.
struct SettingsViewV2: View {
    @AppStorage(V2PreviewFlag.key) private var v2Enabled = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            LazyVStack(spacing: V2Theme.Spacing.section) {
                // Not in the tile grid — a live toggle doesn't fit a
                // tap-to-navigate tile well, and it's a temporary v1
                // fallback control that goes away entirely once v2 is the
                // only design, not a permanent destination worth a slot.
                VStack(alignment: .leading, spacing: 6) {
                    Toggle(isOn: $v2Enabled) {
                        MenuRow(systemImage: "sparkles", title: "New design", floating: true)
                    }
                    Text("Switch off to go back to the classic design.")
                        .font(V2Theme.Typography.metadata)
                        .foregroundStyle(V2Theme.textSecondary)
                }
            }
            .padding(.horizontal, V2Theme.Spacing.horizontal)
            .padding(.vertical, V2Theme.Spacing.section)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .v2TacticsOfficeScene()
        .v2FloatingHeaderWithTiles("Help") {
            V2TileGrid {
                Button {
                    dismiss()
                } label: {
                    V2Tile(icon: "house.fill", label: "HOME", color: V2Theme.textSecondary)
                }
                .buttonStyle(.plain)
                NavigationLink {
                    ProfileSettingsViewV2()
                } label: {
                    V2Tile(icon: "person.crop.circle.fill", label: "PROFILE", color: V2Theme.accent)
                }
                .buttonStyle(.plain)
                NavigationLink {
                    LanguageSettingsViewV2()
                } label: {
                    V2Tile(icon: "globe", label: "LANGUAGE", color: V2Theme.Mode.predictor)
                }
                .buttonStyle(.plain)
            } row2: {
                NavigationLink {
                    AboutViewV2()
                } label: {
                    V2Tile(icon: "info.circle.fill", label: "ABOUT", color: V2Theme.warning)
                }
                .buttonStyle(.plain)
                NavigationLink {
                    ReportBugViewV2()
                } label: {
                    V2Tile(icon: "ladybug.fill", label: "REPORT BUG", color: V2Theme.Mode.killer)
                }
                .buttonStyle(.plain)
                V2TileBlank()
            }
        }
    }
}
