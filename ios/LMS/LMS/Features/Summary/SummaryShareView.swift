import SwiftUI

/// Loads the team data, builds the `SummaryData`, renders the §13b card to a
/// `UIImage`, previews it, and offers the system share sheet (spec §13b.5).
struct SummaryShareView: View {
    @Environment(\.dismiss) private var dismiss
    let game: Game
    let round: Round
    let type: SummaryType

    @State private var teamsById: [Int: TeamDTO] = [:]
    @State private var rendered: UIImage?
    @State private var isLoading = true
    @State private var errorMessage: String?

    private var title: String {
        switch type {
        case .fixtures: return String(localized: "Fixtures · Round \(round.roundNumber)")
        case .picks:    return String(localized: "Picks · Round \(round.roundNumber)")
        case .results:  return String(localized: "Results · Round \(round.roundNumber)")
        case .outcome:  return String(localized: "Outcome · Round \(round.roundNumber)")
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
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .shadow(radius: 8)
                            .padding()
                    }
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
                        // No ad here — the rewarded ad is gated on opening this card
                        // (see GameDetailView), so the share itself is unblocked.
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
        // Team data drives tiles/names; the fixtures card also needs the round's
        // matches. Degrade gracefully to ids/empty if offline.
        var roundFixtures: [FixtureDTO] = []
        do {
            let leagueData = try await LeagueData.load(for: game.leagues)
            teamsById = leagueData.teamsById
            let ids = Set(round.fixtureIds)
            roundFixtures = leagueData.fixtures.filter { ids.contains($0.id) }
        } catch {
            // Non-fatal — render with "Team <id>" fallbacks rather than failing.
            teamsById = [:]
        }
        let managerId = game.players.first(where: { $0.isManager })?.id
        let data = SummaryData.make(type: type, game: game, round: round, teamsById: teamsById,
                                    roundFixtures: roundFixtures, managerPlayerId: managerId)
        let renderer = ImageRenderer(content: SummaryCardView(data: data))
        renderer.scale = 3.0   // @3x — crisp in WhatsApp (spec §13b.4)
        if let image = renderer.uiImage {
            rendered = image
        } else {
            errorMessage = String(localized: "The card image could not be generated.")
        }
        isLoading = false
    }
}
