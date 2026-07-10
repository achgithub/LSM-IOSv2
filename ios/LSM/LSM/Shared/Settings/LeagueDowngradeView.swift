import SwiftUI
import SwiftData

/// Shown when more leagues are enabled than the subscription allows (e.g. a
/// cancelled/downgraded plan) — either opened voluntarily from the
/// grace-period banner (`forced == false`, normally dismissable) or forced
/// full-screen once the 14-day grace period has fully elapsed
/// (`EnabledLeagues.mustBlock`, `forced == true`, non-dismissable). Removing
/// a league deletes any game that uses it — same destructive rule as the
/// Settings checklist (`LeagueSettingsView`); this screen exists because a
/// forced block has no other path back to Settings.
struct LeagueDowngradeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Entitlements.self) private var entitlements
    @Environment(EnabledLeagues.self) private var enabled
    @Environment(\.modelContext) private var context
    @Query private var games: [Game]

    var forced: Bool

    @State private var pendingRemove: LeagueOption?
    @State private var showPaywall = false
    @State private var purchaseAlert: PurchaseAlertItem?

    private var allowance: Int { entitlements.leagueAllowance }
    private var overBy: Int { max(0, enabled.ids.count - allowance) }

    private func gamesUsing(_ league: LeagueOption) -> [Game] {
        games.filter { $0.leagues.contains(league) }
    }

    /// The banner message — differs for the forced-block state vs. the
    /// still-in-grace-period state (opened early from the banner).
    private var overLimitMessage: String {
        let base = allowance == 1
            ? AppString("Your plan now includes 1 league. You have \(enabled.ids.count) enabled.")
            : AppString("Your plan now includes \(allowance) leagues. You have \(enabled.ids.count) enabled.")
        if forced {
            return base + " " + AppString("Subscribe, restore, or remove \(overBy) to continue.")
        }
        if let days = enabled.graceDaysRemaining(entitlements) {
            let countdown = days == 1
                ? AppString("1 day left before extra leagues pause.")
                : AppString("\(days) days left before extra leagues pause.")
            return base + " " + countdown
        }
        return base
    }

    /// Remove-confirm message — singular / plural / no-games variants.
    private func removeMessage(_ league: LeagueOption) -> String {
        let n = gamesUsing(league).count
        switch n {
        case 0:  return AppString("Removes \(league.name) from this device.")
        case 1:  return AppString("Removes \(league.name) from this device and permanently deletes 1 game that uses it — here and in the cloud.")
        default: return AppString("Removes \(league.name) from this device and permanently deletes \(n) games that use it — here and in the cloud.")
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label {
                        Text(verbatim: overLimitMessage)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                }

                Section {
                    Button("Subscribe") { showPaywall = true }
                    Button("Restore Purchases") {
                        Task {
                            let outcome = await PurchaseService.shared.restore()
                            if let a = outcome.alert(restoring: true) {
                                purchaseAlert = PurchaseAlertItem(title: a.title, message: a.message)
                            }
                        }
                    }
                } footer: {
                    Text("Subscribing or restoring instantly covers all your current leagues — nothing is removed either way.")
                }

                Section("Or remove leagues to fit your plan") {
                    ForEach(enabled.leagues) { league in
                        HStack {
                            Text(league.name)
                            Spacer()
                            Button("Remove", role: .destructive) { pendingRemove = league }
                                .buttonStyle(.borderless)
                        }
                    }
                }

                #if DEBUG
                Section {
                    Button("Simulate 7 Leagues (testing)") { entitlements.setDevTier(.leagues7) }
                } footer: {
                    Text("Dev only: unlock the top league tier without a purchase (persists across rebuilds).")
                }
                #endif
            }
            .navigationTitle(allowance == 1
                             ? AppString("Choose your league")
                             : AppString("Choose your leagues"))
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(forced)
            .toolbar {
                if !forced {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView().environment(entitlements)
            }
            .alert(item: $purchaseAlert) { a in
                Alert(title: Text(a.title), message: Text(a.message), dismissButton: .default(Text("OK")))
            }
            .confirmationDialog(
                "Remove \(pendingRemove?.name ?? "")?",
                isPresented: Binding(get: { pendingRemove != nil }, set: { if !$0 { pendingRemove = nil } }),
                titleVisibility: .visible,
                presenting: pendingRemove
            ) { league in
                Button("Remove & delete games", role: .destructive) { remove(league) }
                Button("Cancel", role: .cancel) {}
            } message: { league in
                Text(verbatim: removeMessage(league))
            }
        }
    }

    private func remove(_ league: LeagueOption) {
        for game in gamesUsing(league) { GameLogicService.deleteGame(game, context: context) }
        enabled.disable(league)
        pendingRemove = nil
    }
}
