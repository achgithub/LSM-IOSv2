import SwiftUI

/// Publish a Predictor game's predictions league to a PIN-gated page (§0).
/// Predictor-only — LMS has no predictions league to publish. The manager
/// sets/changes the PIN on every publish (a fresh salt+hash is written
/// server-side each call — see worker/src/routes/publish.ts); the link id is
/// stable across republishes so the same `/l/<id>` keeps working.
struct PublishPredictorView: View {
    @Environment(\.dismiss) private var dismiss
    let game: Game

    @AppStorage private var linkIdRaw: String
    @State private var pin = ""
    @State private var isPublishing = false
    @State private var errorMessage: String?
    @State private var publishedLink: String?

    init(game: Game) {
        self.game = game
        _linkIdRaw = AppStorage(wrappedValue: "", "publishLinkId.\(game.id.uuidString)")
    }

    private var existingLinkId: UUID? { UUID(uuidString: linkIdRaw) }
    private var canPublish: Bool { pin.trimmingCharacters(in: .whitespaces).count >= 4 }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("PIN (4+ digits)", text: $pin)
                        .keyboardType(.numberPad)
                } header: {
                    Text("PIN")
                } footer: {
                    Text("Anyone with the link needs this PIN to see results — weekly scores are per-person. Republishing lets you change it.")
                }

                if let publishedLink {
                    Section("Link") {
                        Text(publishedLink)
                            .textSelection(.enabled)
                            .font(.callout.monospaced())
                        ShareLink(item: publishedLink)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(existingLinkId == nil ? "Publish League" : "Republish League")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await publish() }
                    } label: {
                        if isPublishing { ProgressView() } else { Text(existingLinkId == nil ? "Publish" : "Republish") }
                    }
                    .disabled(!canPublish || isPublishing)
                }
            }
        }
    }

    private func publish() async {
        isPublishing = true
        errorMessage = nil
        defer { isPublishing = false }
        do {
            let data = try await LeagueData.load(for: game.leagues)
            let snapshot = PublishSnapshotBuilder.build(for: game, data: data)
            let id = try await SnapshotClient.shared.publish(snapshot, pin: pin, existingLinkId: existingLinkId)
            linkIdRaw = id.uuidString
            publishedLink = "https://lsm.pages.dev/l/\(id.uuidString)"
        } catch {
            errorMessage = "Couldn't publish: \(error.localizedDescription)"
        }
    }
}
