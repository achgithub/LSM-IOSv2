import Foundation
import SwiftData

/// A Last Man Standing game. Local on-device source of truth (app-driven model).
@Model
final class Game {
    @Attribute(.unique) var id: UUID
    var name: String
    var season: String
    var statusRaw: String
    var allowRepeats: Bool
    var anonymityModeRaw: String
    /// Result rules (§6.5a): a win always survives and a loss always eliminates
    /// — these two are configurable. Defaults match classic Last Man Standing
    /// (draw eliminates) while treating a postponed fixture as a non-event
    /// (survives, since the match never happened). Set once at creation.
    var drawEliminates: Bool = true
    var postponedEliminates: Bool = false
    /// The most recent tie / all-eliminated resolution, so its outcome card stays
    /// shareable from the game screen. nil until a tie has been resolved.
    var lastOutcomeRaw: String?
    var createdAt: Date
    /// True for games created by the interactive "Show Me" demo walkthrough. Marks
    /// every demo game (and, by cascade, its players/rounds/picks) so demo content
    /// can be identified and cleared without touching the manager's real games. New
    /// property defaults to false → existing games migrate as non-demo. See
    /// `DemoDataService`.
    var isDemoData: Bool = false
    /// The league(s) this game runs in (chosen at creation from the enabled
    /// leagues). Usually one, but a game can blend several. Rounds draw fixtures
    /// from these. Empty on legacy games → `leagues` resolves to the home league.
    var leagueIdsRaw: [String] = []
    /// Discriminates LMS (elimination) vs Predictor (score prediction) games
    /// sharing this one model — see `GameMode`. Defaults to `.lms` so existing
    /// games migrate unchanged.
    var modeRaw: String = GameMode.lms.rawValue

    // Predictor scoring config (§0 "best enabled rung" model) — set once at
    // creation, prefilled from the manager's last-used settings. Unused by
    // LMS games. Each rung is independently toggleable; a prediction earns
    // the single highest enabled rung it qualifies for.
    var predictorExactPoints: Int = 4
    var predictorGDEnabled: Bool = true
    var predictorGDPoints: Int = 3
    var predictorResultEnabled: Bool = true
    var predictorResultPoints: Int = 2
    /// One double-points fixture per matchday per player, off by default.
    var predictorJokerEnabled: Bool = false

    // Cloud Publish (Phase 2, Predictor only) — set at GAME level, not typed in
    // on every publish: a 6-digit PIN, generated once on first Publish and
    // reused on every republish until the manager explicitly resets it. The
    // manager shares it however they like (it's going on share cards
    // alongside the link, per Andrew 2026-06-25 — not meant to be retyped).
    /// nil until the game has been published for the first time.
    var predictorPublishPin: String?
    /// The stable `/l/<id>` link id, nil until first published.
    var predictorPublishLinkIdRaw: String?
    /// High-entropy republish credential, minted server-side on first publish
    /// and required on every later one — the PIN above is viewer-only and
    /// deliberately NOT accepted as proof of ownership (a security review
    /// flagged the earlier draft that did: brute-forcing a 6-digit PIN would
    /// have let anyone steal/relock someone else's link, not just view it).
    /// See worker/src/routes/publish.ts.
    var predictorPublishOwnerToken: String?

    // Cloud Submissions (Phase 3) — the client-generated game identity token
    // used to group all player links and round pushes for this game on the
    // Worker. Nil until the first round push fires (lazy mint: if the manager
    // never enables pwaSubmissionsEnabled, this stays nil forever and no
    // resources are consumed). Stored raw so SwiftData can persist it; the
    // typed wrapper is the read-only accessor.
    var cloudGameTokenRaw: String?

    /// Typed accessor; nil if PWA submissions have never been activated.
    var cloudGameToken: UUID? { cloudGameTokenRaw.flatMap(UUID.init) }

    @Relationship(deleteRule: .cascade, inverse: \Player.game)
    var players: [Player] = []

    @Relationship(deleteRule: .cascade, inverse: \Round.game)
    var rounds: [Round] = []

    init(
        name: String,
        season: String,
        allowRepeats: Bool,
        anonymityMode: AnonymityMode = .named,
        leagueIds: [String] = [Leagues.home.id],
        drawEliminates: Bool = true,
        postponedEliminates: Bool = false,
        isDemoData: Bool = false,
        mode: GameMode = .lms,
        predictorExactPoints: Int = 4,
        predictorGDEnabled: Bool = true,
        predictorGDPoints: Int = 3,
        predictorResultEnabled: Bool = true,
        predictorResultPoints: Int = 2,
        predictorJokerEnabled: Bool = false
    ) {
        self.id = UUID()
        self.name = name
        self.season = season
        self.statusRaw = GameStatus.setup.rawValue
        self.allowRepeats = allowRepeats
        self.anonymityModeRaw = anonymityMode.rawValue
        self.createdAt = Date()
        self.leagueIdsRaw = leagueIds.isEmpty ? [Leagues.home.id] : leagueIds
        self.drawEliminates = drawEliminates
        self.postponedEliminates = postponedEliminates
        self.isDemoData = isDemoData
        self.modeRaw = mode.rawValue
        self.predictorExactPoints = predictorExactPoints
        self.predictorGDEnabled = predictorGDEnabled
        self.predictorGDPoints = predictorGDPoints
        self.predictorResultEnabled = predictorResultEnabled
        self.predictorResultPoints = predictorResultPoints
        self.predictorJokerEnabled = predictorJokerEnabled
    }

    /// The league(s) this game runs in (legacy empty → home). Resolved through
    /// `Leagues.lookup` so a demo game's local-only league (never in `Leagues.all`)
    /// still resolves to itself rather than silently falling back to the home
    /// league — otherwise the demo would read the real PL cache. See `Leagues.demo`.
    var leagues: [LeagueOption] {
        let resolved = leagueIdsRaw.compactMap { Leagues.lookup($0) }
        return resolved.isEmpty ? [Leagues.home] : resolved
    }

    /// A short label for the game's league(s): the name if one, else a count.
    var leagueLabel: String {
        let ls = leagues
        return ls.count == 1 ? ls[0].name : ls.map(\.shortName).joined(separator: " · ")
    }

    // Typed wrappers over the stored raw strings.
    var status: GameStatus {
        get { GameStatus(rawValue: statusRaw) ?? .setup }
        set { statusRaw = newValue.rawValue }
    }
    var anonymityMode: AnonymityMode {
        get { AnonymityMode(rawValue: anonymityModeRaw) ?? .named }
        set { anonymityModeRaw = newValue.rawValue }
    }
    var lastOutcome: OutcomeEnding? {
        get { lastOutcomeRaw.flatMap(OutcomeEnding.init(rawValue:)) }
        set { lastOutcomeRaw = newValue?.rawValue }
    }
    var mode: GameMode {
        get { GameMode(rawValue: modeRaw) ?? .lms }
        set { modeRaw = newValue.rawValue }
    }
    var predictorPublishLinkId: UUID? {
        get { predictorPublishLinkIdRaw.flatMap(UUID.init(uuidString:)) }
        set { predictorPublishLinkIdRaw = newValue?.uuidString }
    }

    /// Generates a fresh 6-digit publish PIN (e.g. for "Reset PIN") — not
    /// auto-applied; the caller decides when to overwrite
    /// `predictorPublishPin` (first publish, or an explicit reset).
    static func generatePublishPin() -> String {
        String(format: "%06d", Int.random(in: 0...999_999))
    }

    var activePlayers: [Player] { players.filter { $0.status == .active } }
    var currentRound: Round? { rounds.max(by: { $0.roundNumber < $1.roundNumber }) }

    /// Next sequential entry number for a player added to this game.
    var nextEntryNumber: Int { (players.map(\.entryNumber).max() ?? 0) + 1 }

    /// Total distinct teams a player could ever pick = the sum of the game's
    /// leagues' team counts (from config, so it's available without loading data).
    /// Used to detect team-pool exhaustion when resolving a tie.
    var totalTeamCount: Int { leagues.reduce(0) { $0 + $1.teamsCount } }
}
