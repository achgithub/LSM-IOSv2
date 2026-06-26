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

    var shareItems: [Any] {
        let message = "Hi \(playerName), here's your personal link to submit your pick. Save it as a bookmark or add it to your home screen so you can find it each week:\n\(url.absoluteString)"
        return [message]
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
