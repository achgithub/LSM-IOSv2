import SwiftUI
import SwiftData

/// Card restyle of `LeagueSettingsView` — same two-step disable confirmation,
/// same single-league-plan swap flow, logic copied verbatim (list-based
/// `Button`/checkmark rows don't translate directly to a card layout, so
/// this isn't a shared component with the original — same precedent as
/// `OpenRoundViewV2`).
struct LeagueSettingsViewV2: View {
    @Environment(Entitlements.self) private var entitlements
    @Environment(EnabledLeagues.self) private var enabled
    @Environment(\.modelContext) private var context
    @Query private var games: [Game]

    @State private var pendingDisable: LeagueOption?
    @State private var confirmDisable: LeagueOption?
    @State private var pendingSwap: LeagueOption?

    private var allowance: Int { entitlements.leagueAllowance }

    private func gamesUsing(_ league: LeagueOption) -> [Game] {
        games.filter { $0.leagues.contains(league) }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: V2Theme.Spacing.section) {
                Card(floating: true) {
                    VStack(spacing: 10) {
                        ForEach(Leagues.all) { league in
                            leagueRow(league)
                        }
                    }
                }
                Text(verbatim: leagueFooter)
                    .font(.caption)
                    .foregroundStyle(V2Theme.textSecondary)
                    .padding(.horizontal, 4)
            }
            .padding(.horizontal, V2Theme.Spacing.horizontal)
            .padding(.vertical, V2Theme.Spacing.section)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .v2DataRoomScene()
        .v2FloatingHeader("Leagues")
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

    private func disableMessage(_ league: LeagueOption) -> String {
        let n = gamesUsing(league).count
        switch n {
        case 0:  return AppString("Disabling \(league.name) removes its data from this device.")
        case 1:  return AppString("Disabling \(league.name) removes its data from this device and deletes 1 game that uses it — here and in the cloud.")
        default: return AppString("Disabling \(league.name) removes its data from this device and deletes \(n) games that use it — here and in the cloud.")
        }
    }

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
        let locked = !isOn && atCap && allowance > 1
        Button {
            toggle(league)
        } label: {
            HStack {
                Text(league.name)
                    .font(V2Theme.Typography.rowTitle)
                    .foregroundStyle(locked ? V2Theme.textTertiary : V2Theme.textPrimary)
                Spacer()
                if isOn {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(V2Theme.accent)
                } else if locked {
                    Image(systemName: "lock.fill").foregroundStyle(V2Theme.textTertiary)
                } else {
                    Image(systemName: "circle").foregroundStyle(V2Theme.textTertiary)
                }
            }
        }
        .disabled(locked)
    }

    // MARK: Toggle / disable

    private func toggle(_ league: LeagueOption) {
        if enabled.isEnabled(league) {
            guard enabled.ids.count > 1 else { return }
            pendingDisable = league
        } else if enabled.ids.count < allowance {
            enabled.enable(league)
        } else if allowance == 1 {
            pendingSwap = league
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
