import SwiftUI

/// Branded image shared alongside a player's submission link — gives the link
/// a trustworthy, on-brand visual (recognisable shield/app name) instead of a
/// bare UUID URL that reads as suspicious to less tech-savvy players. The QR
/// code is a bonus for face-to-face handoff (manager shows their screen, the
/// player scans with their own phone) — it can't help someone opening this on
/// the device the link was sent to, since you can't scan your own screen; the
/// tap-through link (shared as a separate item, see `PlayerLinkShareItem`)
/// remains the actual way in for a remotely-sent link.
struct PlayerLinkCardView: View {
    let playerName: String
    let url: URL

    private let palette = ShareCardPalette.lms

    var body: some View {
        VStack(spacing: 0) {
            header
            VStack(spacing: 18) {
                Text("Hi \(playerName) 👋")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(palette.textPrimary)
                Text("Tap the link below to submit your picks.")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(palette.textSecondary)
                    .multilineTextAlignment(.center)
                if let qrImage = QRCodeGenerator.image(for: url.absoluteString) {
                    Image(uiImage: qrImage)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 160, height: 160)
                        .padding(12)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                Text("Face to face? Scan this with your camera instead.")
                    .font(.system(size: 12))
                    .foregroundStyle(palette.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            Divider().overlay(palette.textSecondary.opacity(0.3))
            Text("One link works for all your games.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(palette.textSecondary)
                .padding(.vertical, 16)
        }
        .frame(width: 390)
        .background(palette.bg)
    }

    private var header: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 12)
                .fill(palette.accent)
                .frame(width: 64, height: 64)
                .overlay(
                    Image("shield")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(palette.bg)
                        .padding(10)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text("Your Submission Link")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(palette.textPrimary)
                Text("Last Stand Manager")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(palette.headerBar)
    }
}
