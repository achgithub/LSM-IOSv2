import SwiftUI

/// Publish a Predictor game's predictions league to a PIN-gated page (§0).
/// Predictor-only — LMS has no predictions league to publish.
///
/// The PIN lives on the GAME (`Game.predictorPublishPin`), not retyped on
/// every publish — generated automatically the first time, reused on every
/// republish, and only changes if the manager explicitly resets it (Andrew,
/// 2026-06-25: it's going on share cards alongside the link, so re-entering
/// it each time would be friction with no security upside). The link id is
/// likewise stored on the game (`predictorPublishLinkId`), so it survives a
/// Cloud Backup/restore too.
struct PublishPredictorView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var game: Game

    @State private var isPublishing = false
    @State private var errorMessage: String?
    @State private var didPublish = false
    @State private var pendingResetConfirm = false
    @State private var pendingUnpublishConfirm = false
    @State private var isUnpublishing = false

    /// The live Cloudflare Pages project for published Predictor leagues
    /// (deployed 2026-06-25; see pages/README.md).
    static let pagesBaseURL = "https://lsm-publish.pages.dev"

    private var hasPublishedBefore: Bool { game.predictorPublishLinkId != nil }
    private var publishedLink: String? {
        guard let id = game.predictorPublishLinkId else { return nil }
        let region = game.predictorPublishLinkRegion ?? "uk"
        return "\(PublishPredictorView.pagesBaseURL)/l/\(region)/\(id.uuidString.lowercased())"
    }

    var body: some View {
        NavigationStack {
            Form {
                if let pin = game.predictorPublishPin, let link = publishedLink {
                    Section {
                        Text(link).textSelection(.enabled).font(.callout.monospaced())
                        LabeledContent("PIN", value: pin).font(.callout.monospaced())
                        ShareLink(item: "\(link)\nPIN: \(pin)")
                        Button("Reset PIN", role: .destructive) { pendingResetConfirm = true }
                        Button(role: .destructive) { pendingUnpublishConfirm = true } label: {
                            if isUnpublishing { ProgressView() } else { Text("Unpublish") }
                        }
                        .disabled(isUnpublishing)
                    } header: {
                        Text("Link & PIN")
                    } footer: {
                        Text(didPublish
                             ? "Published just now."
                             : "Share this link and PIN together (e.g. on a share card) — anyone with both can see results.")
                    }
                } else {
                    Section {
                        Text("Publishing generates a link and a 6-digit PIN, both yours to share with the group.")
                            .foregroundStyle(.secondary)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(hasPublishedBefore ? "Republish League" : "Publish League")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await publish() }
                    } label: {
                        if isPublishing { ProgressView() } else { Text(hasPublishedBefore ? "Republish" : "Publish") }
                    }
                    .disabled(isPublishing)
                }
            }
            .confirmationDialog(
                "Reset the PIN?",
                isPresented: $pendingResetConfirm,
                titleVisibility: .visible
            ) {
                Button("Reset & Republish", role: .destructive) {
                    Task { await publish(newPin: Game.generatePublishPin()) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Generates a new PIN and republishes immediately. Anyone using the old PIN will need the new one.")
            }
            .confirmationDialog(
                "Unpublish this league?",
                isPresented: $pendingUnpublishConfirm,
                titleVisibility: .visible
            ) {
                Button("Unpublish", role: .destructive) { Task { await unpublish() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The link stops working immediately for anyone who has it. You can publish again later, which generates a new link.")
            }
        }
    }

    /// `newPin`, when given (the Reset PIN flow), replaces the game's PIN.
    /// The republish credential is `predictorPublishOwnerToken` — NOT the
    /// PIN (see `SnapshotClient.publish`'s doc comment for why that changed).
    ///
    /// `allowFreshRetry` lets a republish that's rejected for lacking a valid
    /// owner token (e.g. a link published before that column existed, from
    /// pre-launch testing) self-heal by minting a brand-new link instead of
    /// leaving the manager stuck — there's no real ownership to recover for
    /// a link republished from this exact app, so starting fresh is correct,
    /// not a workaround. Only ever retries once.
    private func publish(newPin: String? = nil, allowFreshRetry: Bool = true) async {
        isPublishing = true
        errorMessage = nil
        didPublish = false
        defer { isPublishing = false }

        let pinToSet = newPin ?? game.predictorPublishPin ?? Game.generatePublishPin()

        do {
            let data = try await LeagueData.load(for: game.leagues)
            let snapshot = PublishSnapshotBuilder.build(for: game, data: data)
            let result = try await SnapshotClient.shared.publish(
                snapshot, pin: pinToSet,
                existingLinkId: game.predictorPublishLinkId,
                ownerToken: game.predictorPublishOwnerToken
            )
            game.predictorPublishPin = pinToSet
            game.predictorPublishLinkId = result.id
            game.predictorPublishOwnerToken = result.ownerToken
            game.predictorPublishLinkRegion = result.region
            didPublish = true
        } catch APIError.badStatus(401, _) where allowFreshRetry && game.predictorPublishLinkId != nil {
            game.predictorPublishLinkId = nil
            game.predictorPublishOwnerToken = nil
            game.predictorPublishLinkRegion = nil
            await publish(newPin: newPin, allowFreshRetry: false)
        } catch {
            // Include the id we attempted, so a "not found" can be cross-checked
            // against the server's publish_links table directly if needed.
            let attemptedId = game.predictorPublishLinkId?.uuidString ?? "(new)"
            errorMessage = "Couldn't publish (id: \(attemptedId)): \(error.localizedDescription)"
        }
    }

    /// Purges the link server-side (R2 snapshot + D1 row, issue #8) and clears
    /// every publish-related field on `Game` so a future Publish mints a
    /// fresh link rather than trying to reuse the now-deleted one.
    private func unpublish() async {
        guard let id = game.predictorPublishLinkId, let ownerToken = game.predictorPublishOwnerToken else { return }
        isUnpublishing = true
        errorMessage = nil
        defer { isUnpublishing = false }
        do {
            try await SnapshotClient.shared.unpublish(id: id, ownerToken: ownerToken)
            game.predictorPublishLinkId = nil
            game.predictorPublishPin = nil
            game.predictorPublishOwnerToken = nil
            game.predictorPublishLinkRegion = nil
            didPublish = false
        } catch {
            errorMessage = "Couldn't unpublish: \(error.localizedDescription)"
        }
    }
}
