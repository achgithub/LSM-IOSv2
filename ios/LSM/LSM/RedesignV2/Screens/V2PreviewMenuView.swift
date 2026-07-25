import SwiftUI

/// Debug-only entry point into the V2 redesign — a portal-style menu of
/// links to each restyled screen, built as they're added. Not part of the
/// shipping app; wired into `RootTabView` behind `#if DEBUG` only.
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
