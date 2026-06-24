import SwiftUI

/// Subtle premium-feeling tint shown behind a screen's content, instead of
/// the default plain white/gray. Pair with `.scrollContentBackground(.hidden)`
/// on any List/Form in front of it so the system's opaque list background
/// doesn't hide it.
///
/// This is a gradient, NOT the brand system's photographic floodlight image
/// (`docs/brand/sources/background_floodlights.png`) — that image is mostly
/// dark navy, so blending it at an opacity low enough to stay readable on a
/// light background just averages out to flat gray with no visible
/// structure. A gradient echoing the brand's master blue keeps a hint of
/// colour without that mush, and avoids the image-geometry pitfall that bit
/// SplashView.swift on a physical device (see memory lms-brand-system).
struct AppBackground: View {
    var body: some View {
        ZStack {
            Color(.systemBackground)
            LinearGradient(
                colors: [Brand.sharedBlue.opacity(0.12), Color(.systemBackground).opacity(0)],
                startPoint: .top,
                endPoint: UnitPoint(x: 0.5, y: 0.35)
            )
        }
        .ignoresSafeArea()
    }
}

extension View {
    /// Apply the app-wide background tint behind a screen's List/Form,
    /// hiding the system's opaque list background so it shows through.
    /// One call site per screen — tweak the look itself in `AppBackground`.
    func appBackground() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(AppBackground())
    }
}
