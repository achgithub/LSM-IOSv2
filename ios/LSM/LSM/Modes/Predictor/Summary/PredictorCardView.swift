import SwiftUI

/// Shareable Predictor round card. Pure function of `PredictorCardData`; rendered
/// to a UIImage via ImageRenderer. Uses the shared `ShareCardChrome` (dark navy +
/// sky blue) so it's instantly distinct from LMS cards (dark green + gold).
struct PredictorCardView: View {
    let data: PredictorCardData

    private let p = ShareCardPalette.predictor
    private let gold   = Color(hex: "F0C030")
    private let silver = Color(hex: "C0C0C0")
    private let bronze = Color(hex: "CD7F32")

    var body: some View {
        ShareCardChrome(
            palette: .predictor,
            badgeText: "PRED",
            headerLabel: "MATCHDAY",
            roundNumber: data.matchdayNumber,
            gameName: data.gameName,
            appName: data.appName,
            sectionLabel: data.type.sectionLabel,
            timestampLabel: data.timestampLabel
        ) {
            content
        } footer: {
            predictorFooter
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch data.type {
        case .fixtures:      fixturesContent
        case .entryClosed:   entryClosedContent
        case .weeklyResults: weeklyResultsContent
        case .league:        leagueContent
        case .winner:        winnerContent
        }
    }

    @ViewBuilder
    private var fixturesContent: some View {
        if data.fixtures.isEmpty {
            Text("No fixtures for this matchday.")
                .font(.system(size: 15)).foregroundStyle(p.textSecondary)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(data.fixtures) { fixture in
                    HStack(spacing: 8) {
                        Text(fixture.homeName)
                            .font(.system(size: 15, weight: .semibold)).foregroundStyle(p.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .trailing).lineLimit(1)
                        Text("v").font(.system(size: 13)).foregroundStyle(p.textSecondary)
                        Text(fixture.awayName)
                            .font(.system(size: 15, weight: .semibold)).foregroundStyle(p.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading).lineLimit(1)
                        if let kickoff = fixture.kickoff {
                            Text(kickoff, format: .dateTime.weekday(.abbreviated).hour().minute())
                                .font(.system(size: 11)).foregroundStyle(p.textSecondary)
                                .frame(width: 64, alignment: .trailing).lineLimit(1)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var entryClosedContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(data.entrantCount)")
                .font(.system(size: 48, weight: .heavy, design: .rounded))
                .foregroundStyle(p.accent)
            Text(data.entrantCount == 1 ? "entry this matchday" : "entries this matchday")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(p.textPrimary)
        }
    }

    @ViewBuilder
    private var weeklyResultsContent: some View {
        if data.weeklyResults.isEmpty {
            Text("No results yet.")
                .font(.system(size: 15)).foregroundStyle(p.textSecondary)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(data.weeklyResults) { row in
                    HStack(spacing: 10) {
                        Text("\(row.position)")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(p.textSecondary)
                            .frame(width: 24, alignment: .trailing)
                        Text(row.playerName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(p.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .lineLimit(1)
                        Text("\(row.points) pts")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(p.accent)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var leagueContent: some View {
        if data.standings.isEmpty {
            Text("No standings yet.")
                .font(.system(size: 15)).foregroundStyle(p.textSecondary)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                // Header row
                HStack(spacing: 10) {
                    Text("").frame(width: 24)
                    Text("Player")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(p.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Wk")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(p.textSecondary)
                        .frame(width: 32, alignment: .trailing)
                    Text("Tot")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(p.textSecondary)
                        .frame(width: 36, alignment: .trailing)
                }
                .padding(.bottom, 6)
                ForEach(data.standings) { row in
                    HStack(spacing: 10) {
                        Text("\(row.position)")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(p.textSecondary)
                            .frame(width: 24, alignment: .trailing)
                        Text(row.playerName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(p.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .lineLimit(1)
                        if let wk = row.thisRoundPoints {
                            Text("+\(wk)")
                                .font(.system(size: 13))
                                .foregroundStyle(p.textSecondary)
                                .frame(width: 32, alignment: .trailing)
                        } else {
                            Text("—")
                                .font(.system(size: 13))
                                .foregroundStyle(p.textSecondary)
                                .frame(width: 32, alignment: .trailing)
                        }
                        Text("\(row.totalPoints)")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(p.accent)
                            .frame(width: 36, alignment: .trailing)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    @ViewBuilder
    private var winnerContent: some View {
        if data.podium.isEmpty {
            Text("No standings yet.")
                .font(.system(size: 15)).foregroundStyle(p.textSecondary)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(data.podium) { entry in
                    HStack(spacing: 12) {
                        Text(medalEmoji(entry.position))
                            .font(.system(size: 28))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.playerName)
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(p.textPrimary)
                            Text("\(entry.totalPoints) pts")
                                .font(.system(size: 13))
                                .foregroundStyle(medalColor(entry.position))
                        }
                        Spacer()
                        Text(positionLabel(entry.position))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(medalColor(entry.position))
                    }
                }
            }
        }
    }

    private func medalEmoji(_ position: Int) -> String {
        switch position {
        case 1: return "🥇"
        case 2: return "🥈"
        default: return "🥉"
        }
    }

    private func medalColor(_ position: Int) -> Color {
        switch position {
        case 1: return gold
        case 2: return silver
        default: return bronze
        }
    }

    private func positionLabel(_ position: Int) -> String {
        switch position {
        case 1: return "1st"
        case 2: return "2nd"
        default: return "3rd"
        }
    }

    // MARK: Footer

    private var predictorFooter: some View {
        VStack(spacing: 6) {
            Text("\(data.entrantCount) \(data.entrantCount == 1 ? "player" : "players") · Matchday \(data.matchdayNumber)")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(p.accent)
            Text(data.appName)
                .font(.system(size: 11))
                .foregroundStyle(p.textSecondary)
        }
    }
}

// MARK: - Previews

#Preview("Predictor · Fixtures") {
    PredictorCardView(data: .preview(type: .fixtures))
}

#Preview("Predictor · Entry Closed") {
    PredictorCardView(data: .preview(type: .entryClosed))
}

#Preview("Predictor · Weekly Results") {
    PredictorCardView(data: .preview(type: .weeklyResults))
}

#Preview("Predictor · League") {
    PredictorCardView(data: .preview(type: .league))
}

#Preview("Predictor · Winner") {
    PredictorCardView(data: .preview(type: .winner))
}

private extension PredictorCardData {
    static func preview(type: PredictorCardType) -> PredictorCardData {
        let p1 = UUID(); let p2 = UUID(); let p3 = UUID()
        let p4 = UUID(); let p5 = UUID()
        return PredictorCardData(
            type: type,
            gameName: "The Office Pool",
            appName: "Predictor: Premier League",
            leagueName: "Premier League",
            matchdayNumber: 5,
            entrantCount: 12,
            timestampLabel: type == .fixtures ? "Deadline · Fri 1 Aug · 19:45"
                                              : "Matchday 5",
            fixtures: [
                SummaryFixture(id: 1, homeName: "Arsenal", awayName: "Chelsea", kickoff: .now),
                SummaryFixture(id: 2, homeName: "Man Utd", awayName: "Liverpool", kickoff: .now.addingTimeInterval(7200)),
                SummaryFixture(id: 3, homeName: "Man City", awayName: "Spurs", kickoff: .now.addingTimeInterval(86400))
            ],
            weeklyResults: [
                PredictorWeekResult(id: p1, position: 1, playerName: "Andy",  points: 12),
                PredictorWeekResult(id: p2, position: 2, playerName: "Dave",  points: 9),
                PredictorWeekResult(id: p3, position: 2, playerName: "Sarah", points: 9),
                PredictorWeekResult(id: p4, position: 4, playerName: "Pete",  points: 6),
                PredictorWeekResult(id: p5, position: 5, playerName: "Lucy",  points: 4)
            ],
            standings: [
                PredictorStandingEntry(id: p1, position: 1, playerName: "Andy",  totalPoints: 45, thisRoundPoints: 12),
                PredictorStandingEntry(id: p3, position: 2, playerName: "Sarah", totalPoints: 38, thisRoundPoints: 9),
                PredictorStandingEntry(id: p2, position: 3, playerName: "Dave",  totalPoints: 34, thisRoundPoints: 9),
                PredictorStandingEntry(id: p4, position: 4, playerName: "Pete",  totalPoints: 29, thisRoundPoints: 6),
                PredictorStandingEntry(id: p5, position: 5, playerName: "Lucy",  totalPoints: 21, thisRoundPoints: 4)
            ],
            podium: [
                PredictorPodiumEntry(id: p1, position: 1, playerName: "Andy",  totalPoints: 45),
                PredictorPodiumEntry(id: p3, position: 2, playerName: "Sarah", totalPoints: 38),
                PredictorPodiumEntry(id: p2, position: 2, playerName: "Dave",  totalPoints: 38),
                PredictorPodiumEntry(id: p4, position: 3, playerName: "Pete",  totalPoints: 29)  // no 3rd if tied 2nd
            ]
        )
    }
}
