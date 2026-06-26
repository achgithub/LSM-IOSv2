import SwiftUI
import SwiftData
import UIKit

/// Cloud Backup (Phase 2) — explicit, user-triggered R2 snapshot of every
/// on-device game, mode-agnostic (LMS + Predictor together). Lives in
/// Settings since it acts on the whole device, not one game. Gated on the
/// standalone `cloudBundle` entitlement (independent of the league tiers).
struct CloudBackupSection: View {
    @Environment(Entitlements.self) private var entitlements
    @Environment(\.modelContext) private var context
    @Query private var games: [Game]

    @AppStorage("cloudBackupRestoreCode") private var restoreCodeRaw = ""
    @State private var isWorking = false
    @State private var statusMessage: String?
    @State private var showRestorePrompt = false
    @State private var restoreCodeInput = ""
    @State private var showPaywall = false

    private var restoreCode: UUID? { UUID(uuidString: restoreCodeRaw) }

    var body: some View {
        Section {
            if entitlements.canUseCloud {
                Button {
                    Task { await backUpNow() }
                } label: {
                    if isWorking { ProgressView() } else { Text("Back Up Now") }
                }
                .disabled(isWorking || games.isEmpty)

                Button("Restore…") { showRestorePrompt = true }
                    .disabled(isWorking)

                if let restoreCode {
                    LabeledContent("Restore Code", value: restoreCode.uuidString)
                        .textSelection(.enabled)
                    HStack {
                        Button {
                            UIPasteboard.general.string = restoreCode.uuidString
                            statusMessage = "Restore code copied."
                        } label: {
                            Label("Copy Code", systemImage: "doc.on.doc")
                        }
                        Spacer()
                        ShareLink(item: restoreCode.uuidString) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                    }
                    .font(.caption)
                }
                if let statusMessage {
                    Text(statusMessage).font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Button("Unlock Cloud Backup") { showPaywall = true }
            }
        } header: {
            Text("Cloud Backup")
        } footer: {
            Text(entitlements.canUseCloud
                 ? "Backs up every game on this device. Save your restore code somewhere safe (or share it) — it's the only way to restore, on this phone or any other. No account, so anyone with the code can use it."
                 : "Back up all your games to the cloud and restore them on a new phone. One-time setup, no account needed.")
        }
        .alert("Restore from code", isPresented: $showRestorePrompt) {
            TextField("Restore code", text: $restoreCodeInput)
            Button("Restore") { Task { await restore() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter the restore code shown when this backup was made.")
        }
        .sheet(isPresented: $showPaywall) {
            CloudBundlePaywallView()
        }
    }

    private func backUpNow() async {
        isWorking = true
        statusMessage = nil
        defer { isWorking = false }
        let id = restoreCode ?? UUID()
        let bundle = BackupBundle(games: games.map(GameSnapshotBuilder.snapshot(of:)))
        do {
            try await SnapshotClient.shared.backup(bundle, id: id)
            restoreCodeRaw = id.uuidString
            statusMessage = "Backed up \(games.count) game\(games.count == 1 ? "" : "s") just now."
        } catch {
            statusMessage = "Backup failed: \(error.localizedDescription)"
        }
    }

    private func restore() async {
        guard let id = UUID(uuidString: restoreCodeInput.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            statusMessage = "That doesn't look like a valid restore code."
            return
        }
        isWorking = true
        statusMessage = nil
        defer { isWorking = false }
        do {
            let bundle = try await SnapshotClient.shared.restore(id: id)
            for snapshot in bundle.games {
                GameSnapshotBuilder.restore(snapshot, into: context)
            }
            restoreCodeRaw = id.uuidString
            statusMessage = "Restored \(bundle.games.count) game\(bundle.games.count == 1 ? "" : "s")."
        } catch {
            statusMessage = "Restore failed: \(error.localizedDescription)"
        }
    }
}

/// Minimal paywall for the standalone cloud entitlement — separate from
/// `PaywallView` (the league-tier ladder), since this is a single on/off
/// purchase, not a tier picker.
struct CloudBundlePaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Entitlements.self) private var entitlements
    @State private var isPurchasing = false
    @State private var alertItem: PurchaseAlertItem?

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Cloud Backup").font(.title2.bold())
                Text("Back up every game on this device to the cloud, and restore them on a new phone. No account needed — just a restore code.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                Button {
                    Task { await purchase() }
                } label: {
                    if isPurchasing { ProgressView() } else { Text("Subscribe") }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isPurchasing)
            }
            .padding()
            .navigationTitle("Cloud Backup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .alert(item: $alertItem) { a in
                Alert(title: Text(a.title), message: Text(a.message), dismissButton: .default(Text("OK")))
            }
        }
    }

    private func purchase() async {
        isPurchasing = true
        defer { isPurchasing = false }
        let outcome = await PurchaseService.shared.purchaseCloudBundle()
        if let a = outcome.alert(restoring: false) {
            alertItem = PurchaseAlertItem(title: a.title, message: a.message)
        }
        if case .success = outcome { dismiss() }
    }
}
