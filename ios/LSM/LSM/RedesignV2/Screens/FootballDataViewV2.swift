import Combine
import SwiftUI

/// Reached from Home's LEAGUES tile (see `GamesOverviewSummary`) — a small
/// picker between the two real football-data screens (league table,
/// fixtures), plus the "Update football data" refresh action that used to
/// live inline on Home's now-removed `FootballDataCard`. Distinct from
/// `LeagueSettingsViewV2` (which league allowances a manager has enabled),
/// distinct from `SyncCoordinator`'s "Sync" (game rounds/submissions, not
/// football provider data). See `FootballDataStore` for the throttle/ad-gate
/// rationale.
struct FootballDataViewV2: View {
    @Environment(EnabledLeagues.self) private var enabled
    @Environment(\.dismiss) private var dismiss
    @State private var store = FootballDataStore()

    private var updateLabel: String { store.isLoading ? "UPDATING…" : "UPDATE" }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                statusLine
                    .padding(14)
                    .v2FloatingCard()
            }
            .padding(.horizontal, V2Theme.Spacing.horizontal)
            .padding(.vertical, V2Theme.Spacing.section)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .v2DataRoomScene()
        // Leagues/Fixtures/Update moved from a plain menu-row list into the
        // shared tile grid, matching Games/Players — the disclaimer/status
        // text is the only thing left that isn't an action, so that's all
        // that's left as body content.
        .v2FloatingHeaderWithTiles("Football Data") {
            V2TileGrid {
                Button {
                    dismiss()
                } label: {
                    V2Tile(icon: "house.fill", label: "HOME", color: V2Theme.textSecondary)
                }
                .buttonStyle(.plain)
                NavigationLink {
                    MatchesViewV2()
                } label: {
                    V2Tile(icon: "sportscourt", label: "FIXTURES", color: V2Theme.warning)
                }
                .buttonStyle(.plain)
                NavigationLink {
                    StandingsViewV2()
                } label: {
                    V2Tile(value: "\(enabled.ids.count)", label: "LEAGUES", color: V2Theme.warning)
                }
                .buttonStyle(.plain)
            } row2: {
                Button {
                    store.refresh(leagues: enabled.leagues)
                } label: {
                    V2Tile(icon: "arrow.clockwise", label: updateLabel, color: V2Theme.accent)
                }
                .buttonStyle(.plain)
                .disabled(store.isLoading || store.isThrottled)
                NavigationLink {
                    LeagueSettingsViewV2()
                } label: {
                    V2Tile(icon: "slider.horizontal.3", label: "MANAGE", color: V2Theme.Mode.predictor)
                }
                .buttonStyle(.plain)
                // Subscription moved here from the old dedicated Settings
                // screen — it gates league allowance (see MANAGE above), so
                // it belongs next to it rather than in the Help catch-all.
                NavigationLink {
                    SubscriptionSettingsViewV2()
                } label: {
                    V2Tile(icon: "star.fill", label: "SUBSCRIPTION", color: V2Theme.warning)
                }
                .buttonStyle(.plain)
            }
        }
        .v2LoadingOverlay(store.isLoading, label: "Updating football data…")
        // Only advance the clock while throttled, matching MatchesView's
        // rationale — no re-render churn once the button is already live.
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { tick in
            if store.isThrottled { store.now = tick }
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        VStack(spacing: 4) {
            if store.isThrottled, let freshUntil = store.freshUntil {
                let remaining = Duration.seconds(max(0, freshUntil.timeIntervalSince(store.now)))
                Text("Update available in \(remaining.formatted(.time(pattern: .minuteSecond)))")
                    .font(.caption2)
                    .foregroundStyle(V2Theme.textSecondary)
            } else if let lastRefreshed = store.lastRefreshed {
                Text("Updated \(lastRefreshed.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(V2Theme.textSecondary)
            } else if let errorMessage = store.errorMessage {
                Text(errorMessage)
                    .font(.caption2)
                    .foregroundStyle(V2Theme.danger)
            }
            Text(DataDisclaimer.text)
                .font(.caption2)
                .foregroundStyle(V2Theme.textTertiary)
                .multilineTextAlignment(.center)
        }
    }
}
