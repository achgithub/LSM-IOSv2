import SwiftUI

/// Entry point into the V2 redesign — a portal-style menu of links to each
/// restyled screen, built as they're added. Reached via the "V2" tab, which
/// `RootTabView` only shows when the user opts in from Settings (see
/// `V2PreviewFlag`) — off by default, works in every build, not `#if DEBUG`.
struct V2PreviewMenuView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 14) {
                    NavigationLink {
                        GamesPortalViewV2()
                    } label: {
                        MenuRow(systemImage: "trophy", title: "Games (portal)")
                    }
                    .buttonStyle(.plain)
                    NavigationLink {
                        StandingsViewV2()
                    } label: {
                        MenuRow(systemImage: "list.number", title: "Standings (reference)")
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
}
