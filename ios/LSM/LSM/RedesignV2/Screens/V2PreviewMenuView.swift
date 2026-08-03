import SwiftUI

/// Entry point into the V2 redesign — a portal-style menu of links to each
/// restyled screen, built as they're added. Reached via a row at the bottom
/// of Settings (see `SettingsView`), shown only when the user opts in via
/// `V2PreviewFlag` — off by default, works in every build, not `#if DEBUG`.
///
/// Pushed into Settings' own `NavigationStack` rather than owning one itself
/// — an embedded `NavigationStack` here, combined with `.v2Header`'s custom
/// back button, used to produce a stray extra back arrow (this view wrapped
/// its own root in `.v2Header`, which draws a back button even with nothing
/// to dismiss) on top of the real one Settings already provides.
struct V2PreviewMenuView: View {
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                NavigationLink {
                    GamesPortalViewV2()
                } label: {
                    MenuRow(systemImage: "trophy", title: "Portal")
                }
                .buttonStyle(.plain)
                NavigationLink {
                    PlayersViewV2()
                } label: {
                    MenuRow(systemImage: "person.2", title: "Players")
                }
                .buttonStyle(.plain)
                NavigationLink {
                    MatchesViewV2()
                } label: {
                    MenuRow(systemImage: "sportscourt", title: "Fixtures")
                }
                .buttonStyle(.plain)
                NavigationLink {
                    StandingsViewV2()
                } label: {
                    MenuRow(systemImage: "list.number", title: "Leagues")
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, V2Theme.Spacing.horizontal)
            .padding(.vertical, V2Theme.Spacing.section)
        }
        .background(V2Theme.background.ignoresSafeArea())
        .v2Header("V2 Preview")
    }
}
