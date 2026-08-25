import SwiftUI
import StoreKit

/// Card restyle of `SubscriptionSettingsView` — plan status, upgrade/
/// restore, and (debug builds only) the tier simulator.
struct SubscriptionSettingsViewV2: View {
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
        ScrollView {
            LazyVStack(spacing: V2Theme.Spacing.section) {
                Card(floating: true) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Plan").foregroundStyle(V2Theme.textSecondary)
                            Spacer()
                            Text(entitlements.tier.label).foregroundStyle(V2Theme.textPrimary).fontWeight(.semibold)
                        }
                        .font(V2Theme.Typography.rowTitle)
                        Text(entitlements.tier.detail)
                            .font(.caption)
                            .foregroundStyle(V2Theme.textSecondary)
                        if entitlements.tier != .leagues7 {
                            ActionRow(title: "Upgrade", icon: "star.fill") { showPaywall = true }
                        }
                        ActionRow(title: "Restore Purchases", icon: "arrow.clockwise") {
                            Task {
                                let outcome = await PurchaseService.shared.restore()
                                if let a = outcome.alert(restoring: true) {
                                    purchaseAlert = PurchaseAlertItem(title: a.title, message: a.message)
                                }
                            }
                        }
                    }
                }

                #if DEBUG
                Card(floating: true) {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Developer (testing)")
                        Picker("Simulate tier", selection: tierBinding) {
                            ForEach(Tier.allCases) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.menu)
                        .tint(V2Theme.accent)
                        Text("Flips ad-on / ad-off + league allowance without a purchase. Free/No Ads = 1, then 3 / 5 / 7 leagues by tier.")
                            .font(.caption).foregroundStyle(V2Theme.textSecondary)
                        ActionRow(title: "Check StoreKit Products (bypass RevenueCat)", icon: "checklist") {
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
                            Text(diagnostic).font(.caption).foregroundStyle(V2Theme.textSecondary)
                        }
                    }
                }
                #endif
            }
            .padding(.horizontal, V2Theme.Spacing.horizontal)
            .padding(.vertical, V2Theme.Spacing.section)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .v2DataRoomScene()
        .v2FloatingHeader("Subscription")
        .sheet(isPresented: $showPaywall) {
            PaywallView().environment(entitlements)
        }
        .alert(item: $purchaseAlert) { a in
            Alert(title: Text(a.title), message: Text(a.message), dismissButton: .default(Text("OK")))
        }
    }
}
