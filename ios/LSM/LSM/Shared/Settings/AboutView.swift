import SwiftUI

/// App/version info, data attribution, and legal links.
struct AboutView: View {
    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }

    var body: some View {
        List {
            Section {
                LabeledContent("App", value: Leagues.app.name)
                LabeledContent("Version", value: version)
                // Attribution required by the football-data.org licence: a
                // visible "Data provided by football-data.org" credit. Brand
                // name kept verbatim so it reads identically in every language.
                Link(destination: URL(string: "https://www.football-data.org")!) {
                    Text(verbatim: "Data provided by football-data.org")
                }
                Link("Privacy Policy", destination: URL(string: "https://sportsmanager-site.pages.dev/lsm/privacy")!)
                Link("Terms of Service", destination: URL(string: "https://sportsmanager-site.pages.dev/lsm/terms")!)
                // Apple requires a link to its standard EULA (or a custom one
                // containing Apple's mandated minimum terms — ours above
                // doesn't) since subscriptions are sold via In-App Purchase.
                // Keep this alongside our own terms.html, not instead of it.
                Link("Terms of Use (EULA)", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
            } footer: {
                // Single localized string key — can't wrap without changing the key.
                // swiftlint:disable:next line_length
                Text("Not affiliated with, licensed by or endorsed by any football club, league or federation. An independent tool — team names and fixtures are factual data shown for reference only.")
            }
        }
        .appBackground()
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}
