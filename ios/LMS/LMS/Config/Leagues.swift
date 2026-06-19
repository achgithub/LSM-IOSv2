import Foundation

/// A league the user can browse / run rounds against. Each is a separate Worker
/// deployment backed by a free-tier football-data feed. Loaded from the bundled
/// `leagues.json` manifest so adding a league (the app is built to support many)
/// is a data edit, never a code change — add the Worker + a manifest entry.
struct LeagueOption: Identifiable, Hashable, Sendable, Decodable {
    let id: String          // leagueId, e.g. "PL"
    let name: String        // display name, e.g. "Premier League"
    let shortName: String   // chip label, e.g. "PL"
    let workerBaseURL: String
    let teamsCount: Int
    /// True for the standalone screenshot/demo league (frozen data, no live
    /// feed) — visible only in DEBUG builds, see `Leagues.all`. Defaults to
    /// false since most manifest entries omit the key entirely.
    let devOnly: Bool

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        shortName = try c.decode(String.self, forKey: .shortName)
        workerBaseURL = try c.decode(String.self, forKey: .workerBaseURL)
        teamsCount = try c.decode(Int.self, forKey: .teamsCount)
        devOnly = try c.decodeIfPresent(Bool.self, forKey: .devOnly) ?? false
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, shortName, workerBaseURL, teamsCount, devOnly
    }

    var workerURL: URL {
        guard let url = URL(string: workerBaseURL) else {
            fatalError("Invalid workerBaseURL in leagues.json for \(id): \(workerBaseURL)")
        }
        return url
    }

    var client: APIClient { APIClient(baseURL: workerURL) }
}

/// The registry of every league with a live Worker. Single source of truth —
/// the engine, networking and UI all resolve leagues through here, never via a
/// hardcoded id or count, so the set scales by editing `leagues.json` alone.
/// App-wide settings (not league-specific), bundled in `leagues.json`.
struct AppSettings: Decodable, Sendable {
    let name: String                 // product name shown on cards / Settings
    let season: String               // default season for a new game
    let allowRepeatDefault: Bool     // default "allow repeat picks" rule
}

enum Leagues {
    private struct Manifest: Decodable {
        let app: AppSettings
        let homeLeagueId: String
        let leagues: [LeagueOption]
    }

    private static let manifest: Manifest = load()

    /// App-wide settings (product name, default season + gameplay rules).
    static var app: AppSettings { manifest.app }

    /// Every registered league, in manifest order. `devOnly` leagues (the
    /// standalone screenshot/demo league — see leagues.json) only ever appear
    /// in DEBUG builds; a Release/TestFlight/App Store build never sees them.
    static var all: [LeagueOption] {
        #if DEBUG
        manifest.leagues
        #else
        manifest.leagues.filter { !$0.devOnly }
        #endif
    }

    /// The user's configured home league (the one a new game defaults to).
    static var home: LeagueOption { byId(manifest.homeLeagueId) ?? all[0] }

    /// Resolve a league by id (e.g. a round's stored `leagueId`).
    static func byId(_ id: String) -> LeagueOption? {
        all.first { $0.id == id }
    }

    /// Resolve a league by id, falling back to home for unknown/legacy ids.
    static func resolve(_ id: String) -> LeagueOption {
        byId(id) ?? home
    }

    private static func load() -> Manifest {
        guard let url = Bundle.main.url(forResource: "leagues", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            fatalError("leagues.json is missing from the app bundle")
        }
        do {
            let manifest = try JSONDecoder().decode(Manifest.self, from: data)
            guard !manifest.leagues.isEmpty else { fatalError("leagues.json has no leagues") }
            return manifest
        } catch {
            fatalError("Failed to decode leagues.json: \(error)")
        }
    }
}
