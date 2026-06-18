import SwiftUI

/// Brand splash shown once at launch, over the instant (blank) system launch
/// screen. v1 (LMS): a single full-bleed composed image (`splash_lms`) with a
/// simple fade-in. The earlier staged shield→wordmark→name animation is parked
/// until we have clean transparent asset slices (v2).
///
/// Timeline: fade in over ~0.6s, hold ~1.5s, then hand off to the app.
struct SplashView: View {
    /// Called when the splash should hand off to the app.
    var onFinished: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var opacity = 0.0

    var body: some View {
        ZStack {
            // Dark backdrop matches the image's edges so the 16:9 art is shown
            // whole and centred (scaledToFit) with seamless letterboxing on
            // taller screens — no cropping/off-centre.
            Color.black.ignoresSafeArea()

            if let splash = Brand.image("splash_lms") {
                splash
                    .resizable()
                    .scaledToFit()
                    .ignoresSafeArea()
                    .opacity(opacity)
            }
        }
        .task { await run() }
    }

    private func run() async {
        if reduceMotion {
            opacity = 1
        } else {
            withAnimation(.easeIn(duration: 0.6)) { opacity = 1 }
        }
        // Fade (0.6s) + hold (1.5s) before handing off.
        try? await Task.sleep(for: .seconds(0.6 + 1.5))
        onFinished()
    }
}

/// Brand tokens. `accent` is the LMS product colour; swap per product variant.
enum Brand {
    static let accent = Color(hex: "EF4444")

    /// An asset-catalog image by name, or nil if the slot is empty (so a caller
    /// can fall back). Guards against an empty/zero-size imageset.
    static func image(_ name: String) -> Image? {
        #if canImport(UIKit)
        if let ui = UIImage(named: name), ui.size.width > 0 { return Image(uiImage: ui) }
        return nil
        #else
        return nil
        #endif
    }
}

#Preview {
    SplashView()
}
