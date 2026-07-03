import Foundation

// Wire types returned by the Worker (already camelCase JSON). Read-only — the
// cloud serves only provider-sourced sports data.

// TeamDTO and StandingDTO are Codable so the league-data cache can persist them
// to disk (see DiskCache) — that's what makes browsing serve cached data and
// only the ad-gated refresh hit the network.
struct TeamDTO: Codable, Identifiable {
    let id: String
    let externalId: Int
    let name: String
    let shortName: String?
    let tla: String?
    let leagueId: String
}

// Codable (not just Decodable) so the league-data cache can persist matches to
// disk, the same way teams/standings are cached — see LeagueDataCache.
//
// One unified record for a match — schedule (matchday/kickoff, from /fixtures)
// and live state (minute/status/score/winner, from /scores) merged into a
// single on-device representation. There used to be a separate FixtureDTO and
// ScoreItem with the same match duplicated across two caches that had to be
// reconciled after the fact (`patchFixturesCache`); merging removes that
// reconciliation step entirely — there's only ever one copy to update.
// `/fixtures`' wire JSON decodes straight into this (no `minute` key there,
// so it's just nil); `/scores`' wire JSON decodes into `ScoreDTO` and is
// merged in by `LeagueData.pullLiveMatches`, which overlays the live fields.
struct MatchDTO: Codable, Identifiable {
    let id: Int
    let matchday: Int?
    let kickoff: String
    let status: String
    let minute: Int?
    let homeTeamId: Int
    let awayTeamId: Int
    let homeScore: Int?
    let awayScore: Int?
    let winner: String?
    /// Which league this match was fetched from — absent on the wire (each
    /// Worker serves one league per request), so `LeagueData.load` stamps it
    /// right after fetching, before anything else sees it. Deliberately NOT
    /// inferred from team-roster membership: a promoted/relegated club can
    /// briefly appear in two leagues' team lists at once, which would
    /// mislabel a match based on roster-sync timing rather than which
    /// league it actually belongs to.
    var leagueId: String?

    /// Undated matches (no parseable kickoff) sort last; otherwise by kickoff
    /// then id.
    nonisolated static func byKickoffThenId(_ a: MatchDTO, _ b: MatchDTO) -> Bool {
        switch (FixtureFormat.kickoffDate(a.kickoff), FixtureFormat.kickoffDate(b.kickoff)) {
        case let (x?, y?): return x == y ? a.id < b.id : x < y
        case (nil, _?): return false
        case (_?, nil): return true
        case (nil, nil): return a.id < b.id
        }
    }
}

struct StandingDTO: Codable, Identifiable {
    let teamId: Int
    var position: Int
    let played: Int
    let won: Int
    let drawn: Int
    let lost: Int
    let goalsFor: Int
    let goalsAgainst: Int
    let goalDifference: Int
    let points: Int
    let updatedAt: String

    var id: Int { teamId }

    /// The Worker's own `position`/row order is authoritative once any real
    /// results exist. The one case it isn't: pre-season, when every row is
    /// 0-0-0 and some providers return those ties in ID order rather than
    /// the alphabetical convention used league-wide for level teams — so
    /// that specific all-zero case is re-sorted alphabetically (by the same
    /// shortName the row displays, not the provider's full official name)
    /// and renumbered client-side; any other table is passed through
    /// untouched.
    nonisolated static func displayOrder(rows: [StandingDTO], teamsById: [Int: TeamDTO]) -> [StandingDTO] {
        let allScoreless = rows.allSatisfy { $0.points == 0 && $0.goalDifference == 0 && $0.goalsFor == 0 }
        guard allScoreless else { return rows }
        let sorted = rows.sorted { a, b in
            let teamA = teamsById[a.teamId]
            let teamB = teamsById[b.teamId]
            let nameA = teamA?.shortName ?? teamA?.name ?? ""
            let nameB = teamB?.shortName ?? teamB?.name ?? ""
            return nameA.localizedCaseInsensitiveCompare(nameB) == .orderedAscending
        }
        return sorted.enumerated().map { index, row in
            var row = row
            row.position = index + 1
            return row
        }
    }
}

struct ScoreDTO: Decodable, Identifiable {
    let id: Int
    let status: String
    let minute: Int?
    let homeTeamId: Int
    let awayTeamId: Int
    let homeScore: Int?
    let awayScore: Int?
    let winner: String?
}
