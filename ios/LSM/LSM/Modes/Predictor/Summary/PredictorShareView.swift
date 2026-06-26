import SwiftUI

/// Loads team data, builds `PredictorCardData`, renders via ImageRenderer @3x,
/// previews the result, and exposes the system share sheet. Mirrors the
/// `SummaryShareView` pattern from LMS.
struct PredictorShareView: View {
    @Environment(\.dismiss) private var dismiss
    let game: Game
    let round: Round
    let type: PredictorCardType

    @State private var rendered: UIImage?
    @State private var isLoading = true
    @State private var errorMessage: String?

    private var title: String {
        switch type {
        case .fixtures:      return AppString("Fixtures · Matchday \(round.roundNumber)")
        case .entryClosed:   return AppString("Entries Closed · Matchday \(round.roundNumber)")
        case .weeklyResults: return AppString("Results · Matchday \(round.roundNumber)")
        case .league:        return AppString("League Table · Matchday \(round.roundNumber)")
        case .winner:        return AppString("Final Standings")
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let rendered {
                    ScrollView {
                        Image(uiImage: rendered)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 390)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .shadow(radius: 8)
                            .padding()
                    }
                    .frame(maxWidth: .infinity)
                } else if let errorMessage {
                    ContentUnavailableView("Couldn't build card", systemImage: "photo.badge.exclamationmark",
                                           description: Text(errorMessage))
                } else {
                    ProgressView("Rendering card…")
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                if let rendered {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            ImageSharePresenter.present(image: rendered, title: title)
                        } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
            .task { await build() }
        }
    }

    private func build() async {
        isLoading = true
        errorMessage = nil
        var teamsById: [Int: TeamDTO] = [:]
        var roundMatches: [MatchDTO] = []
        do {
            let leagueData = try await LeagueData.load(for: game.leagues)
            teamsById = leagueData.teamsById
            let ids = Set(round.fixtureIds)
            roundMatches = leagueData.matches.filter { ids.contains($0.id) }
        } catch {
            // Non-fatal — fixture card degrades to empty list; other cards unaffected.
        }
        let data = PredictorCardData.make(
            type: type, game: game, round: round,
            teamsById: teamsById, roundMatches: roundMatches
        )
        let renderer = ImageRenderer(
            content: PredictorCardView(data: data).environment(\.locale, Bundle.appLocale)
        )
        renderer.scale = 3.0
        if let image = renderer.uiImage {
            rendered = image
        } else {
            errorMessage = AppString("The card image could not be generated.")
        }
        isLoading = false
    }
}
