import Foundation

/// The game modes that share LSM's engine, models and cloud backend.
///
/// v1 shipped only the elimination game (now `.lms` at the mode level); v2 adds
/// `.predictor` alongside it in the same app, under one subscription. `.killer`
/// adds a third mode: numeric lives, a Build/Kill phase split, and an
/// adversarial "Hit" targeting mechanic — see the Killer implementation plan.
/// The mode is the discriminator on a `Game` (mirrors `games.mode` in the
/// Worker schema). See docs/lsm-v2-architecture.md §1.
enum GameMode: String, Codable, CaseIterable, Identifiable {
    /// Last Man Standing — one pick per round, wrong/no pick eliminates, last
    /// player standing wins. Ported from v1, now cloud-backed.
    case lms
    /// Season-long score prediction — points for correct outcome/home/away score,
    /// accumulating into a running league table. No elimination. New in v2.
    case predictor
    /// Lives-based elimination with a Build Phase (earn lives) then a Kill
    /// Phase (predictions also fire a Hit at a chosen opponent). On-device only
    /// for now — no cloud/PWA support yet.
    case killer

    var id: String { rawValue }

    /// User-facing mode name. Note the app brand is "Last Stand Manager" (LSM);
    /// this is the *mode* name shown inside it.
    var displayName: String {
        switch self {
        case .lms: return "Last Man Standing"
        case .predictor: return "Predictor"
        case .killer: return "Killer"
        }
    }
}
