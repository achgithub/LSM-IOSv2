import Foundation

/// A league the user can browse / run rounds against. Each is a separate Worker
/// deployment backed by a free-tier football-data feed. Loaded from the
/// registry manifest (cached on disk, falling back to the bundled
/// `leagues.json` on a fresh install) so adding a league is a data edit, never
/// a code change or app update — see `Leagues.refreshFromRegistry`.
struct LeagueOption: Identifiable, Hashable, Sendable, Codable {
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

    // Manual (not synthesized) so this stays in sync with the custom decoder
    // above — needed because this type is also cached to disk by
    // `LeagueDataCache.save` (see Leagues.refreshFromRegistry).
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(shortName, forKey: .shortName)
        try c.encode(workerBaseURL, forKey: .workerBaseURL)
        try c.encode(teamsCount, forKey: .teamsCount)
        try c.encode(devOnly, forKey: .devOnly)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, shortName, workerBaseURL, teamsCount, devOnly
    }

    /// `name` with the "Country — " prefix stripped (e.g. "La Liga" from
    /// "España — La Liga") — recognizable to a customer who's never seen the
    /// bare competition code, but still compact enough for a filter chip.
    /// Derived from `name` rather than a separate manifest field, so it scales
    /// to any future league automatically with no extra data to keep in sync.
    var displayName: String {
        guard let range = name.range(of: " — ") else { return name }
        return String(name[range.upperBound...])
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
struct AppSettings: Codable, Sendable {
    let name: String                 // product name shown on cards / Settings
    let season: String               // default season for a new game
    let allowRepeatDefault: Bool     // default "allow repeat picks" rule
}

enum Leagues {
    private struct Manifest: Codable {
        let app: AppSettings
        let homeLeagueId: String
        let leagues: [LeagueOption]
    }

    /// Disk-cache key for the registry's manifest — see `refreshFromRegistry`.
    private static let manifestCacheKey = "registry-manifest"
    private static let registryURL = URL(string: "https://registry.sportsmanager.site/leagues.json")!

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

    /// Disk cache (from a previous `refreshFromRegistry`) first, falling back
    /// to the bundled manifest. The bundle copy is the only thing guaranteed
    /// to exist, so it's the only path that still `fatalError`s on failure —
    /// a missing/corrupt disk cache just means "use the bundle", same as a
    /// fresh install that's never reached the network yet.
    private static func load() -> Manifest {
        if let cached = LeagueDataCache.load(Manifest.self, key: manifestCacheKey), !cached.leagues.isEmpty {
            return cached
        }
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

    /// Fetches the latest league list from the registry worker and caches it
    /// to disk for the **next** launch — `manifest` above is evaluated once
    /// per process, so this never changes what the current run sees. That's
    /// deliberate: it keeps `Leagues.all`/`.home`/`.byId` synchronous, so
    /// nothing downstream (SettingsView, game/round creation) needs to become
    /// async just because the league list can now grow without an app update.
    /// Fire-and-forget; any failure (network, decode, empty list) is silently
    /// ignored, leaving the existing cache/bundle in place untouched.
    static func refreshFromRegistry() async {
        var request = URLRequest(url: registryURL)
        request.timeoutInterval = 5
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return }
        guard let fetched = try? JSONDecoder().decode(Manifest.self, from: data), !fetched.leagues.isEmpty else { return }
        LeagueDataCache.save(fetched, key: manifestCacheKey)
    }
}
