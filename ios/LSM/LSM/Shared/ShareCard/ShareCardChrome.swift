import SwiftUI

/// Reusable share-card shell: fixed 390pt width, header badge + round label,
/// section label row, content area, divider, footer. Parameterised by palette
/// and @ViewBuilder slots so any game mode can drop in its own content/footer.
struct ShareCardChrome<Content: View, Footer: View>: View {
    let palette: ShareCardPalette
    let headerLabel: String
    let roundNumber: Int
    let gameName: String
    let appName: String
    let sectionLabel: String
    let timestampLabel: String
    @ViewBuilder let content: () -> Content
    @ViewBuilder let footer: () -> Footer

    var body: some View {
        VStack(spacing: 0) {
            header
            sectionLabelRow
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            Divider().overlay(palette.textSecondary.opacity(0.3))
            footer()
                .frame(maxWidth: .infinity)
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
                Text(gameName)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(palette.textPrimary)
                Text(appName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text(headerLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
                Text("\(roundNumber)")
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundStyle(palette.accent)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(palette.headerBar)
    }

    private var sectionLabelRow: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(sectionLabel)
                .font(.system(size: 15, weight: .heavy)).tracking(2)
                .foregroundStyle(palette.accent)
            Text(timestampLabel)
                .font(.system(size: 12))
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }
}
