import SwiftUI
import UIKit

/// Wraps a set of file URLs for `.sheet(item:)` — SwiftUI needs an `Identifiable`
/// to drive the sheet's presented/dismissed state from one optional binding.
struct ExportShareItem: Identifiable {
    let urls: [URL]
    var id: String { urls.map(\.path).joined() }
}

/// Drives the player-link share sheet — carries the player name for the
/// personalised message and the URL, both needed to build the share payload.
struct PlayerLinkShareItem: Identifiable {
    let playerName: String
    let url: URL
    var id: String { url.absoluteString }

    /// Shown wherever the link is presented to a player — in-app, in the
    /// share message, and on the card image — so the same phishing-style
    /// caution is consistent everywhere, not just wherever we remembered to
    /// add it.
    static var safetyWarning: String {
        AppString("Only tap this if you were expecting it — check with your manager first if you're not sure.")
    }

    /// Message text shared alongside the card image and URL — a bare UUID
    /// link embedded in a paragraph reads as suspicious to less tech-savvy
    /// players, and burying the URL in text stops Messages/WhatsApp from
    /// rendering their own rich link preview, hence sharing it as its own
    /// separate `URL` value too.
    func message() -> String {
        "Hi \(playerName) 👋 Here's your personal link to submit your picks. "
            + "Save it as a bookmark or add it to your Home Screen so you can find it each week.\n\n"
            + "⚠️ \(PlayerLinkShareItem.safetyWarning)"
    }
}

/// Renders the player-link card, previews it, then offers the system share
/// sheet — the same preview-then-share pattern as `SummaryShareView`/
/// `PredictorShareView`, which has never had trouble sharing over AirDrop.
/// The player-link flow used to skip the preview and hand the freshly
/// rendered `UIImage` straight to the share sheet; that turned out to
/// matter — an unpreviewed image was serialized as a corrupted/oversized
/// bitmap that AirDrop rejected (`SFAirDropSend.Failure` badRequest).
struct PlayerLinkShareView: View {
    @Environment(\.dismiss) private var dismiss
    let item: PlayerLinkShareItem

    @State private var rendered: UIImage?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if let rendered {
                    ScrollView {
                        Image(uiImage: rendered)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 390)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .shadow(radius: 8)
                            .padding()
                    }
                    .frame(maxWidth: .infinity)
                } else if let errorMessage {
                    ContentUnavailableView("Couldn't build card", systemImage: "photo.badge.exclamationmark",
                                           description: Text(errorMessage))
                } else {
                    ProgressView("Rendering card…")
                }
            }
            .navigationTitle("Submission Link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                if let rendered {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            // AirDrop specifically rejects any multi-item
                            // share from this app (confirmed on-device: 2 or
                            // 3 items both fail with SFAirDropSend.Failure
                            // badRequest; 1 item succeeds) — exclude just
                            // AirDrop here rather than drop the message/link
                            // for every channel. Messages/WhatsApp/Mail all
                            // handle the full 3-item share fine. Face-to-face
                            // handoff is covered separately by the in-app QR
                            // (PlayersView "Show In Person").
                            ImageSharePresenter.present(
                                items: [rendered, item.message(), item.url],
                                excludedActivityTypes: [.airDrop]
                            )
                        } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
            .task { await build() }
        }
    }

    private func build() async {
        let renderer = ImageRenderer(
            content: PlayerLinkCardView(playerName: item.playerName, url: item.url)
                .environment(\.locale, Bundle.appLocale)
        )
        renderer.scale = 3.0
        if let image = renderer.uiImage {
            rendered = image
        } else {
            errorMessage = AppString("The card image could not be generated.")
        }
    }
}

/// Thin `UIViewControllerRepresentable` around `UIActivityViewController`, so the
/// system share sheet can be triggered after an async step rather than from a
/// `ShareLink` (which needs its items ready synchronously on tap).
/// Items may be `URL`, `String`, or any type `UIActivityViewController` accepts.
struct ActivityShareView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
