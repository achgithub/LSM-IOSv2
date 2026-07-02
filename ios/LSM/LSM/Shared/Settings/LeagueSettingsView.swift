import SwiftUI
import SwiftData

/// League enable/disable checklist, capped by subscription (spec §7.2).
/// Disabling a league removes its on-device data and deletes any game that
/// uses it — guarded by a two-step confirmation.
struct LeagueSettingsView: View {
    @Environment(Entitlements.self) private var entitlements
    @Environment(EnabledLeagues.self) private var enabled
    @Environment(\.modelContext) private var context
    @Query private var games: [Game]

    // Two-step confirmation for disabling a league.
    @State private var pendingDisable: LeagueOption?   // first warning
    @State private var confirmDisable: LeagueOption?   // second (final) warning
    // Single-league plans swap their one league instead of disable/enable.
    @State private var pendingSwap: LeagueOption?

    private var allowance: Int { entitlements.leagueAllowance }

    /// Games that reference a league (whole game is deleted, even if it blends
    /// other leagues too).
    private func gamesUsing(_ league: LeagueOption) -> [Game] {
        games.filter { $0.leagues.contains(league) }
    }

    var body: some View {
        List {
            Section {
                ForEach(Leagues.all) { league in
                    leagueRow(league)
                }
            } footer: {
                Text(verbatim: leagueFooter)
            }
        }
        .appBackground()
        .navigationTitle("Leagues")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Disable \(pendingDisable?.name ?? "league")?",
            isPresented: Binding(get: { pendingDisable != nil }, set: { if !$0 { pendingDisable = nil } }),
            titleVisibility: .visible,
            presenting: pendingDisable
        ) { league in
            Button("Continue", role: .destructive) {
                pendingDisable = nil
                confirmDisable = league
            }
            Button("Cancel", role: .cancel) {}
        } message: { league in
            Text(verbatim: disableMessage(league))
        }
        .confirmationDialog(
            "Delete games in \(confirmDisable?.name ?? "")?",
            isPresented: Binding(get: { confirmDisable != nil }, set: { if !$0 { confirmDisable = nil } }),
            titleVisibility: .visible,
            presenting: confirmDisable
        ) { league in
            Button("Disable & delete", role: .destructive) { disable(league) }
            Button("Cancel", role: .cancel) {}
        } message: { league in
            let n = gamesUsing(league).count
            Text(verbatim: n == 1
                 ? AppString("This permanently deletes 1 game and can't be undone.")
                 : AppString("This permanently deletes \(n) games and can't be undone."))
        }
        .confirmationDialog(
            "Switch to \(pendingSwap?.name ?? "")?",
            isPresented: Binding(get: { pendingSwap != nil }, set: { if !$0 { pendingSwap = nil } }),
            titleVisibility: .visible,
            presenting: pendingSwap
        ) { target in
            Button("Switch", role: .destructive) { swap(to: target) }
            Button("Cancel", role: .cancel) {}
        } message: { target in
            Text(verbatim: switchMessage(to: target))
        }
    }

    /// League-section footer: a base sentence plus an optional "subscribe" nudge
    /// when the catalogue has more leagues than the plan allows. Built in Swift so
    /// each clause is a clean, fully-translatable sentence (no inline plurals).
    private var leagueFooter: String {
        let canSubscribeForMore = allowance < Leagues.all.count
        if allowance == 1 {
            var text = AppString("Your \(entitlements.tier.label) plan includes 1 league — tap another to switch.")
            if canSubscribeForMore { text += " " + AppString("Subscribe to run more at once.") }
            return text
        } else {
            var text = AppString("You can enable \(allowance) leagues on the \(entitlements.tier.label) plan.")
            if canSubscribeForMore { text += " " + AppString("Subscribe to enable more.") }
            return text
        }
    }

    /// First disable-confirm message — singular / plural / no-games variants.
    private func disableMessage(_ league: LeagueOption) -> String {
        let n = gamesUsing(league).count
        switch n {
        case 0:  return AppString("Disabling \(league.name) removes its data from this device.")
        case 1:  return AppString("Disabling \(league.name) removes its data from this device and deletes 1 game that uses it — here and in the cloud.")
        default: return AppString("Disabling \(league.name) removes its data from this device and deletes \(n) games that use it — here and in the cloud.")
        }
    }

    /// Single-league-plan swap-confirm message — singular / plural / no-games.
    private func switchMessage(to target: LeagueOption) -> String {
        let current = enabled.leagues.first?.name ?? AppString("your league")
        let n = enabled.leagues.reduce(0) { $0 + gamesUsing($1).count }
        switch n {
        case 0:  return AppString("Switches from \(current) to \(target.name).")
        case 1:  return AppString("Switches from \(current) to \(target.name), deleting 1 game that uses the old league — here and in the cloud.")
        default: return AppString("Switches from \(current) to \(target.name), deleting \(n) games that use the old league — here and in the cloud.")
        }
    }

    @ViewBuilder
    private func leagueRow(_ league: LeagueOption) -> some View {
        let isOn = enabled.isEnabled(league)
        let atCap = enabled.ids.count >= allowance
        // On a 1-league plan an unselected league is a SWAP target (tappable),
        // not locked. It's only locked when a multi-league plan is at its cap.
        let locked = !isOn && atCap && allowance > 1
        Button {
            toggle(league)
        } label: {
            HStack {
                Text(league.name).foregroundStyle(locked ? .secondary : .primary)
                Spacer()
                if isOn {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                } else if locked {
                    Image(systemName: "lock.fill").foregroundStyle(.secondary)
                } else {
                    Image(systemName: "circle").foregroundStyle(.secondary)
                }
            }
        }
        .disabled(locked)
    }

    // MARK: Toggle / disable

    private func toggle(_ league: LeagueOption) {
        if enabled.isEnabled(league) {
            guard enabled.ids.count > 1 else { return }   // keep at least one
            pendingDisable = league                        // → two-step confirm
        } else if enabled.ids.count < allowance {
            enabled.enable(league)
        } else if allowance == 1 {
            pendingSwap = league                           // swap the one league
        }
    }

    private func swap(to target: LeagueOption) {
        for current in enabled.leagues {
            for game in gamesUsing(current) { GameLogicService.deleteGame(game, context: context) }
        }
        enabled.setOnly(target)
        pendingSwap = nil
    }

    private func disable(_ league: LeagueOption) {
        for game in gamesUsing(league) { GameLogicService.deleteGame(game, context: context) }
        enabled.disable(league)
        confirmDisable = nil
    }
}
