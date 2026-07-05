import UIKit

/// Presents the system share sheet for a rendered image, programmatically, so an
/// export can be triggered *after* a rewarded ad (see AdGate) rather than from a
/// SwiftUI `ShareLink` that fires on tap. Works whether or not the ads SDK is
/// linked (it only uses UIKit).
@MainActor
enum ImageSharePresenter {
    static func present(image: UIImage, title: String) {
        present(items: [image])
    }

    /// Same presentation, for callers sharing the image alongside other
    /// items (e.g. a message and a URL) rather than the image alone.
    ///
    /// `excludedActivityTypes` exists because AirDrop specifically (not
    /// Messages/WhatsApp/Mail) rejects any multi-item share from this app
    /// with `SFAirDropSend.Failure` badRequest — confirmed on-device: a
    /// single-item share succeeds, two or three items both fail identically.
    /// Rather than lose the message/link items for every channel, exclude
    /// just AirDrop where a multi-item share is offered (see
    /// `PlayerLinkShareView`).
    static func present(items: [Any], excludedActivityTypes: [UIActivity.ActivityType] = []) {
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        vc.excludedActivityTypes = excludedActivityTypes
        guard let top = topViewController() else { return }
        // iPad: anchor the popover to the centre of the presenting view.
        if let pop = vc.popoverPresentationController {
            pop.sourceView = top.view
            pop.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 0, height: 0)
            pop.permittedArrowDirections = []
        }
        top.present(vc, animated: true)
    }

    /// The frontmost presented view controller (so we present above any sheet).
    private static func topViewController() -> UIViewController? {
        var top = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
