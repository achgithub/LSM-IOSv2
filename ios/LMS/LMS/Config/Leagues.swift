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
enum Leagues {
    private struct Manifest: Decodable {
        let homeLeagueId: String
        let leagues: [LeagueOption]
    }

    private static let manifest: Manifest = load()

    /// Every registered league, in manifest order.
    static var all: [LeagueOption] { manifest.leagues }

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
