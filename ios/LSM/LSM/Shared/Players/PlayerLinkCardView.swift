import SwiftUI

/// Branded image shared alongside a player's submission link — gives the link
/// a trustworthy, on-brand visual (recognisable shield/app name) instead of a
/// bare UUID URL that reads as suspicious to less tech-savvy players. No QR
/// code here — that's shown in-app instead (see `PlayersView`'s "Show In
/// Person" section), and embedding the CoreImage-rendered QR in this card
/// was implicated in AirDrop transfers failing with a corrupted/oversized
/// image (`SFAirDropSend.Failure` badRequest); dropping it also keeps the
/// card simpler and smaller.
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
                Text("⚠️ \(PlayerLinkShareItem.safetyWarning)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.accent)
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
