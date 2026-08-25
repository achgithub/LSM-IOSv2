import SwiftUI

/// Card restyle of `AboutView` — same app/version info, attribution, and
/// legal links.
struct AboutViewV2: View {
    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: V2Theme.Spacing.section) {
                Card(floating: true) {
                    VStack(alignment: .leading, spacing: 12) {
                        infoRow("App", Leagues.app.name)
                        infoRow("Version", version)
                    }
                }
                Card(floating: true) {
                    VStack(alignment: .leading, spacing: 10) {
                        // Attribution required by the football-data.org licence: a
                        // visible "Data provided by football-data.org" credit. Brand
                        // name kept verbatim so it reads identically in every language.
                        linkRow(AppString("Data provided by football-data.org"), url: "https://www.football-data.org")
                        linkRow(AppString("Privacy Policy"), url: "https://sportsmanager.site/lsm/privacy")
                        linkRow(AppString("Terms of Service"), url: "https://sportsmanager.site/lsm/terms")
                        // Apple requires a link to its standard EULA (or a custom
                        // one containing Apple's mandated minimum terms — ours
                        // doesn't) since subscriptions are sold via In-App
                        // Purchase. Keep alongside our own terms.html, not instead.
                        linkRow(AppString("Terms of Use (EULA)"), url: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")
                    }
                }
                Text("Not affiliated with, licensed by or endorsed by any football club, league or federation. An independent tool — team names and fixtures are factual data shown for reference only.")
                    .font(.caption)
                    .foregroundStyle(V2Theme.textSecondary)
                    .padding(.horizontal, 4)
            }
            .padding(.horizontal, V2Theme.Spacing.horizontal)
            .padding(.vertical, V2Theme.Spacing.section)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .v2TacticsOfficeScene()
        .v2FloatingHeader("About")
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(V2Theme.textSecondary)
            Spacer()
            Text(value).foregroundStyle(V2Theme.textPrimary).fontWeight(.semibold)
        }
        .font(V2Theme.Typography.rowTitle)
    }

    private func linkRow(_ title: String, url: String) -> some View {
        Link(destination: URL(string: url)!) {
            HStack {
                Text(title)
                Spacer()
                Image(systemName: "arrow.up.right").font(.caption)
            }
        }
        .foregroundStyle(V2Theme.accent)
        .font(V2Theme.Typography.rowTitle)
    }
}
