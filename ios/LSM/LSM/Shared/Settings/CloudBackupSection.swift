import SwiftUI
import SwiftData
import UIKit

/// Cloud Backup — explicit, user-triggered R2 snapshot of every on-device
/// game, mode-agnostic (LMS + Predictor together). Lives in Settings since it
/// acts on the whole device, not one game. Gated on `canUseCloud` (leagues_3+).
struct CloudBackupSection: View {
    @Environment(Entitlements.self) private var entitlements
    @Environment(\.modelContext) private var context
    @Query private var games: [Game]
    @Query private var rosterMembers: [RosterMember]
    @Query private var playerGroups: [PlayerGroup]

    @AppStorage("cloudBackupRestoreCode") private var restoreCodeRaw = ""
    @State private var isWorking = false
    @State private var statusMessage: String?
    @State private var showRestorePrompt = false
    @State private var restoreCodeInput = ""
    @State private var showPaywall = false
    @State private var lifecycleStatus: ManagerLifecycleStatus?

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
            VStack(alignment: .leading, spacing: 4) {
                Text(entitlements.canUseCloud
                     // swiftlint:disable:next line_length
                     ? "Backs up every game on this device. Save your restore code somewhere safe (or share it) — it's the only way to restore, on this phone or any other. No account, so anyone with the code can use it."
                     : "Back up all your games to the cloud and restore them on a new phone. One-time setup, no account needed.")
                if let banner = lifecycleStatus?.bannerMessage {
                    Text(banner)
                        .foregroundStyle(lifecycleStatus?.isPendingDelete == true ? .red : .orange)
                }
            }
        }
        .task {
            if entitlements.canUseCloud {
                lifecycleStatus = await ManagerLifecycleClient.shared.status()
                // Re-subscribed during grace period — clear the pending deletion.
                if lifecycleStatus?.isPendingDelete == true {
                    await ManagerLifecycleClient.shared.resubscribe()
                    lifecycleStatus = await ManagerLifecycleClient.shared.status()
                }
            } else if entitlements.verified && !entitlements.canUseCloud {
                // Only schedule deletion once RevenueCat has confirmed the tier —
                // `verified` prevents a false unsubscribe before the first refresh.
                await ManagerLifecycleClient.shared.unsubscribe()
                lifecycleStatus = await ManagerLifecycleClient.shared.status()
            }
        }
        .alert("Restore from code", isPresented: $showRestorePrompt) {
            TextField("Restore code", text: $restoreCodeInput)
            Button("Restore") { Task { await restore() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter the restore code shown when this backup was made.")
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
    }

    private func backUpNow() async {
        isWorking = true
        statusMessage = nil
        defer { isWorking = false }
        let id = restoreCode ?? UUID()
        let bundle = BackupBundle(
            games: games.map(GameSnapshotBuilder.snapshot(of:)),
            managerToken: ManagerToken.current,
            roster: RosterSnapshotBuilder.snapshot(members: rosterMembers, groups: playerGroups)
        )
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
            if let roster = bundle.roster {
                RosterSnapshotBuilder.restore(roster, into: context)
            }
            // Restoring the original device's token (rather than leaving this
            // device's freshly-minted one) is what lets existing submission
            // links, manager_lifecycle status, etc. keep working post-restore
            // — see ManagerToken.restore.
            if let managerToken = bundle.managerToken {
                ManagerToken.restore(managerToken)
            }
            restoreCodeRaw = id.uuidString
            statusMessage = "Restored \(bundle.games.count) game\(bundle.games.count == 1 ? "" : "s")."
        } catch {
            statusMessage = "Restore failed: \(error.localizedDescription)"
        }
    }
}
