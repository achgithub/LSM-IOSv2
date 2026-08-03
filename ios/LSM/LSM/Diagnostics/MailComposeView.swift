import SwiftUI
import MessageUI

/// Thin `UIViewControllerRepresentable` wrapping `MFMailComposeViewController`
/// — SwiftUI has no native mail composer. Mirrors `ActivityShareView`'s shape
/// (a `.sheet`-presented system controller with a dismiss callback).
struct MailComposeView: UIViewControllerRepresentable {
    let recipient: String
    let subject: String
    let body: String
    let attachmentURL: URL?
    var onFinish: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients([recipient])
        controller.setSubject(subject)
        controller.setMessageBody(body, isHTML: false)
        if let attachmentURL, let data = try? Data(contentsOf: attachmentURL) {
            controller.addAttachmentData(data, mimeType: "text/plain", fileName: attachmentURL.lastPathComponent)
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onFinish: () -> Void
        init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }

        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            controller.dismiss(animated: true, completion: onFinish)
        }
    }
}
