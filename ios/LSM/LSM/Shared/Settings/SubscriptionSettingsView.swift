import SwiftUI
import StoreKit

/// Plan status, upgrade / restore, and (debug builds only) the tier simulator.
struct SubscriptionSettingsView: View {
    @Environment(Entitlements.self) private var entitlements
    @State private var showPaywall = false
    @State private var purchaseAlert: PurchaseAlertItem?
    #if DEBUG
    @State private var storeKitDiagnostic: String?

    private var tierBinding: Binding<Tier> {
        Binding(get: { entitlements.tier }, set: { entitlements.setDevTier($0) })
    }
    #endif

    var body: some View {
        List {
            Section {
                LabeledContent("Plan", value: entitlements.tier.label)
                Text(entitlements.tier.detail)
                    .font(.caption).foregroundStyle(.secondary)
                if entitlements.tier != .leagues7 {
                    Button("Upgrade") { showPaywall = true }
                }
                Button("Restore Purchases") {
                    Task {
                        let outcome = await PurchaseService.shared.restore()
                        if let a = outcome.alert(restoring: true) {
                            purchaseAlert = PurchaseAlertItem(title: a.title, message: a.message)
                        }
                    }
                }
            }

            #if DEBUG
            Section("Developer (testing)") {
                Picker("Simulate tier", selection: tierBinding) {
                    ForEach(Tier.allCases) { Text($0.label).tag($0) }
                }
                Text("Flips ad-on / ad-off + league allowance without a purchase. Free/No Ads = 1, then 3 / 5 / 7 leagues by tier.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Check StoreKit Products (bypass RevenueCat)") {
                    Task {
                        let ids = Set(PurchaseOption.all.map { $0.packageId })
                        do {
                            let products = try await Product.products(for: ids)
                            let found = Set(products.map { $0.id })
                            let missing = ids.subtracting(found)
                            let missingText = missing.isEmpty ? "none" : missing.sorted().joined(separator: ", ")
                            storeKitDiagnostic = "Found \(products.count)/\(ids.count): \(found.sorted().joined(separator: ", "))\nMissing: \(missingText)"
                        } catch {
                            storeKitDiagnostic = "Error: \(error)"
                        }
                    }
                }
                if let diagnostic = storeKitDiagnostic {
                    Text(diagnostic).font(.caption).foregroundStyle(.secondary)
                }
            }
            #endif
        }
        .appBackground()
        .navigationTitle("Subscription")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPaywall) {
            PaywallView().environment(entitlements)
        }
        .alert(item: $purchaseAlert) { a in
            Alert(title: Text(a.title), message: Text(a.message), dismissButton: .default(Text("OK")))
        }
    }
}
