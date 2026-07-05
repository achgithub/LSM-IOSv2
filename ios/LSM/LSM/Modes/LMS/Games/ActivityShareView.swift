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
    static let safetyWarning = "Only tap this if you were expecting it — check with your manager first if you're not sure."

    /// Three separate items, not one string with the URL pasted in — a bare
    /// UUID link embedded in a paragraph reads as suspicious to less
    /// tech-savvy players, and burying the URL in text stops Messages/WhatsApp
    /// from rendering their own rich link preview. Sharing the URL as its own
    /// `URL` value gets that preview back; the branded card image (with a QR
    /// code as a face-to-face bonus, see `PlayerLinkCardView`) gives it visual
    /// trust context, especially useful for a bare AirDrop with no chat UI.
    ///
    /// Built asynchronously from a `.task` (see `PlayerLinkShareSheet`), not
    /// read synchronously off `ImageRenderer` the instant the sheet needs
    /// items — that pattern produced a corrupted image on-device that AirDrop
    /// rejected mid-transfer (`SFAirDropSend.Failure` badRequest, reported
    /// size 0). `SummaryShareView`/`PredictorShareView` render inside an
    /// already-appeared view's `.task`, which doesn't hit this; this mirrors
    /// that.
    @MainActor
    func buildShareItems() async -> [Any] {
        var items: [Any] = []
        let renderer = ImageRenderer(
            content: PlayerLinkCardView(playerName: playerName, url: url)
                .environment(\.locale, Bundle.appLocale)
        )
        renderer.scale = 3.0
        if let image = renderer.uiImage {
            items.append(image)
        }
        items.append("Hi \(playerName) 👋 Here's your personal link to submit your picks. "
            + "Save it as a bookmark or add it to your Home Screen so you can find it each week.\n\n"
            + "⚠️ \(PlayerLinkShareItem.safetyWarning)")
        items.append(url)
        return items
    }
}

/// Renders the share-card image in a `.task` (after this view has had a real
/// SwiftUI render pass) before presenting the system share sheet — see
/// `PlayerLinkShareItem.buildShareItems()` for why that ordering matters.
struct PlayerLinkShareSheet: View {
    let item: PlayerLinkShareItem

    @State private var items: [Any]?

    var body: some View {
        Group {
            if let items {
                ActivityShareView(items: items)
            } else {
                ProgressView()
                    .task { items = await item.buildShareItems() }
            }
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
