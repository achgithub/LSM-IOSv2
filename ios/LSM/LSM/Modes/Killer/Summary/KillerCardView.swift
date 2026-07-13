import SwiftUI

/// Shareable Killer round card. Pure function of `KillerCardData`; rendered to
/// a UIImage via ImageRenderer. Uses the shared `ShareCardChrome` with the
/// crimson Killer palette so it's instantly distinct from LMS/Predictor cards.
struct KillerCardView: View {
    let data: KillerCardData

    private let p = ShareCardPalette.killer

    var body: some View {
        ShareCardChrome(
            palette: .killer,
            headerLabel: "ROUND",
            roundNumber: data.roundNumber,
            gameName: data.gameName,
            appName: data.appName,
            sectionLabel: data.type.sectionLabel,
            timestampLabel: data.timestampLabel
        ) {
            content
        } footer: {
            killerFooter
        }
    }

    @ViewBuilder
    private var content: some View {
        switch data.type {
        case .fixtures:      fixturesContent
        case .playerKey:     playerKeyContent
        case .weeklyResults: weeklyResultsContent
        case .standings:     standingsContent
        case .winner:        winnerContent
        }
    }

    @ViewBuilder
    private var fixturesContent: some View {
        if data.fixtures.isEmpty {
            Text("No Manager Picked Games for this round.")
                .font(.system(size: 15)).foregroundStyle(p.textSecondary)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(data.fixtures) { fixture in
                    HStack(spacing: 10) {
                        numberBadge(fixture.number)
                        Text(fixture.homeName)
                            .font(.system(size: 15, weight: .semibold)).foregroundStyle(p.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .trailing).lineLimit(1)
                        Text("v").font(.system(size: 13)).foregroundStyle(p.textSecondary)
                        Text(fixture.awayName)
                            .font(.system(size: 15, weight: .semibold)).foregroundStyle(p.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading).lineLimit(1)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var playerKeyContent: some View {
        if data.playerKey.isEmpty {
            Text("No active players.")
                .font(.system(size: 15)).foregroundStyle(p.textSecondary)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("Use these numbers to text your Hit target.")
                    .font(.system(size: 12)).foregroundStyle(p.textSecondary)
                ForEach(data.playerKey) { entry in
                    HStack(spacing: 10) {
                        numberBadge(entry.number)
                        Text(entry.playerName)
                            .font(.system(size: 15, weight: .semibold)).foregroundStyle(p.textPrimary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var weeklyResultsContent: some View {
        if data.weeklyResults.isEmpty {
            Text("No players yet.")
                .font(.system(size: 15)).foregroundStyle(p.textSecondary)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(data.weeklyResults) { row in
                    HStack(spacing: 8) {
                        Text(row.playerName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(p.textPrimary)
                            .frame(width: 90, alignment: .leading)
                            .lineLimit(1)
                        if row.eliminatedThisRound {
                            Text("☠️").font(.system(size: 15))
                        } else {
                            Text(String(repeating: "❤️", count: row.lives))
                                .font(.system(size: 13))
                            if row.hitsReceived > 0 {
                                Text(String(repeating: "💥", count: row.hitsReceived))
                                    .font(.system(size: 13))
                            }
                        }
                        Spacer()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var standingsContent: some View {
        if data.standings.isEmpty {
            Text("No standings yet.")
                .font(.system(size: 15)).foregroundStyle(p.textSecondary)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Text("Player")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(p.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Lives")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(p.textSecondary)
                        .frame(width: 40, alignment: .trailing)
                    Text("Acc.")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(p.textSecondary)
                        .frame(width: 32, alignment: .trailing)
                }
                .padding(.bottom, 6)
                ForEach(data.standings) { row in
                    HStack(spacing: 10) {
                        Text(row.playerName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(row.isEliminated ? p.textSecondary : p.textPrimary)
                            .strikethrough(row.isEliminated)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .lineLimit(1)
                        Text("\(row.lives)")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(p.accent)
                            .frame(width: 40, alignment: .trailing)
                        Text("\(row.correctPredictions)")
                            .font(.system(size: 13))
                            .foregroundStyle(p.textSecondary)
                            .frame(width: 32, alignment: .trailing)
                    }
                    .padding(.vertical, 4)
                }
                Text("Accuracy is a tiebreak only, not a leaderboard.")
                    .font(.system(size: 11))
                    .foregroundStyle(p.textSecondary)
                    .padding(.top, 6)
            }
        }
    }

    @ViewBuilder
    private var winnerContent: some View {
        if data.winners.isEmpty {
            Text("No winner yet.")
                .font(.system(size: 15)).foregroundStyle(p.textSecondary)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(data.winners) { winner in
                    HStack(spacing: 12) {
                        Text("🏆").font(.system(size: 28))
                        Text(winner.playerName)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(p.textPrimary)
                        Spacer()
                    }
                }
                if data.winners.count > 1 {
                    Text("Split result.")
                        .font(.system(size: 12))
                        .foregroundStyle(p.textSecondary)
                }
            }
        }
    }

    private func numberBadge(_ number: Int) -> some View {
        Text("\(number)")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(p.bg)
            .frame(width: 22, height: 22)
            .background(Circle().fill(p.accent))
    }

    private var killerFooter: some View {
        VStack(spacing: 6) {
            Text(data.entrantCount == 1
                 ? AppString("\(data.entrantCount) player · Round \(data.roundNumber)")
                 : AppString("\(data.entrantCount) players · Round \(data.roundNumber)"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(p.accent)
            Text(data.appName)
                .font(.system(size: 11))
                .foregroundStyle(p.textSecondary)
        }
    }
}

// MARK: - Previews

#Preview("Killer · Fixtures") {
    KillerCardView(data: .preview(type: .fixtures))
}

#Preview("Killer · Player Key") {
    KillerCardView(data: .preview(type: .playerKey))
}

#Preview("Killer · Weekly Results") {
    KillerCardView(data: .preview(type: .weeklyResults))
}

#Preview("Killer · Standings") {
    KillerCardView(data: .preview(type: .standings))
}

#Preview("Killer · Winner") {
    KillerCardView(data: .preview(type: .winner))
}

private extension KillerCardData {
    static func preview(type: KillerCardType) -> KillerCardData {
        let p1 = UUID(); let p2 = UUID(); let p3 = UUID(); let p4 = UUID()
        return KillerCardData(
            type: type,
            gameName: "Sunday League Killer",
            appName: "Killer",
            leagueName: "Premier League",
            roundNumber: 4,
            entrantCount: 8,
            timestampLabel: type == .fixtures || type == .playerKey
                ? "Deadline · Fri 1 Aug · 19:45" : "Round 4",
            fixtures: [
                KillerNumberedFixture(id: 1, number: 1, homeName: "Arsenal", awayName: "Chelsea", kickoff: .now),
                KillerNumberedFixture(id: 2, number: 2, homeName: "Man Utd", awayName: "Liverpool", kickoff: .now),
                KillerNumberedFixture(id: 3, number: 3, homeName: "Man City", awayName: "Spurs", kickoff: .now)
            ],
            playerKey: [
                KillerPlayerKeyEntry(id: p1, number: 1, playerName: "Alex"),
                KillerPlayerKeyEntry(id: p2, number: 2, playerName: "Beth"),
                KillerPlayerKeyEntry(id: p3, number: 3, playerName: "Carl"),
                KillerPlayerKeyEntry(id: p4, number: 4, playerName: "Dana")
            ],
            weeklyResults: [
                KillerWeekResult(id: p1, playerName: "Alex", lives: 4, hitsReceived: 2, eliminatedThisRound: false),
                KillerWeekResult(id: p2, playerName: "Beth", lives: 4, hitsReceived: 0, eliminatedThisRound: false),
                KillerWeekResult(id: p3, playerName: "Carl", lives: 3, hitsReceived: 1, eliminatedThisRound: false),
                KillerWeekResult(id: p4, playerName: "Dana", lives: 0, hitsReceived: 3, eliminatedThisRound: true)
            ],
            standings: [
                KillerStandingEntry(id: p1, playerName: "Alex", lives: 4, correctPredictions: 9,
                                     successfulHitsLanded: 3, isEliminated: false),
                KillerStandingEntry(id: p2, playerName: "Beth", lives: 4, correctPredictions: 7,
                                     successfulHitsLanded: 2, isEliminated: false),
                KillerStandingEntry(id: p3, playerName: "Carl", lives: 3, correctPredictions: 8,
                                     successfulHitsLanded: 1, isEliminated: false),
                KillerStandingEntry(id: p4, playerName: "Dana", lives: 0, correctPredictions: 5,
                                     successfulHitsLanded: 1, isEliminated: true)
            ],
            winners: [
                KillerWinnerEntry(id: p1, playerName: "Alex")
            ]
        )
    }
}
