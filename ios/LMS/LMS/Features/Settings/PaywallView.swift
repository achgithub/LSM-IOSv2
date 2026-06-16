import SwiftUI

/// The in-app upgrade screen — the path the Settings "Upgrade" copy now leads to.
/// Lists the paid tiers with a Subscribe button each, plus Restore, and always
/// reports the outcome (success / failure / unavailable) via an alert so a tap is
/// never a silent no-op. Until RevenueCat is linked + a real key is set, purchases
/// resolve to `.unavailable` and the user is told so, rather than nothing happening.
struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Entitlements.self) private var entitlements

    /// The tier whose button is mid-flight (drives the spinner + disables input).
    @State private var working: Tier?
    @State private var alert: PurchaseAlertItem?

    private let paidTiers: [Tier] = [.noAds, .pro]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(paidTiers) { tier in
                        tierRow(tier)
                    }
                } header: {
                    Text("Choose a plan")
                } footer: {
                    Text("Subscriptions renew automatically until cancelled. Manage or cancel anytime in the App Store under your Apple ID → Subscriptions.")
                }

                Section {
                    Button("Restore Purchases") {
                        Task { await runRestore() }
                    }
                }
            }
            .navigationTitle("Go Premium")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .disabled(working != nil)
            .overlay {
                if working != nil { ProgressView().controlSize(.large) }
            }
            .alert(item: $alert) { a in
                Alert(title: Text(a.title), message: Text(a.message), dismissButton: .default(Text("OK")))
            }
        }
    }

    @ViewBuilder
    private func tierRow(_ tier: Tier) -> some View {
        let isCurrent = entitlements.tier == tier
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(tier.label).font(.headline)
                Spacer()
                if isCurrent {
                    Text("Current").font(.caption).foregroundStyle(.secondary)
                } else {
                    Button("Subscribe") { Task { await runPurchase(tier) } }
                        .buttonStyle(.borderedProminent)
                }
            }
            Text(tier.detail).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func runPurchase(_ tier: Tier) async {
        working = tier
        let outcome = await PurchaseService.shared.purchase(tier)
        working = nil
        present(outcome, restoring: false)
    }

    private func runRestore() async {
        working = .free   // any non-nil value flags "busy"
        let outcome = await PurchaseService.shared.restore()
        working = nil
        present(outcome, restoring: true)
    }

    private func present(_ outcome: PurchaseService.PurchaseOutcome, restoring: Bool) {
        guard let a = outcome.alert(restoring: restoring) else { return }
        alert = PurchaseAlertItem(title: a.title, message: a.message)
    }
}
