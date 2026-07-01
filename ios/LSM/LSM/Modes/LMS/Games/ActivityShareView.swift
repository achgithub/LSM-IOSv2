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

    /// Three separate items, not one string with the URL pasted in — a bare
    /// UUID link embedded in a paragraph reads as suspicious to less
    /// tech-savvy players, and burying the URL in text stops Messages/WhatsApp
    /// from rendering their own rich link preview. Sharing the URL as its own
    /// `URL` value gets that preview back; the branded card image (with a QR
    /// code as a face-to-face bonus, see `PlayerLinkCardView`) gives it visual
    /// trust context, especially useful for a bare AirDrop with no chat UI.
    var shareItems: [Any] {
        var items: [Any] = []
        let renderer = ImageRenderer(content: PlayerLinkCardView(playerName: playerName, url: url))
        renderer.scale = 3.0
        if let image = renderer.uiImage {
            items.append(image)
        }
        items.append("Hi \(playerName) 👋 Here's your personal link to submit your picks. "
            + "Save it as a bookmark or add it to your Home Screen so you can find it each week.")
        items.append(url)
        return items
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
