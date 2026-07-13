import Combine
import Foundation

/// App-wide "this build is too old to talk to the current Worker API" flag —
/// distinct from `MaintenanceState` (temporary backend outage) and never set
/// from an error response. Set from `Leagues.refreshFromRegistry` after
/// decoding the registry manifest's `minVersion`, so it's checked once per
/// launch rather than on every cloud call. A hard block (unlike the
/// dismissible maintenance banner): a genuinely breaking API change means the
/// app can't function correctly against the current backend, so there's no
/// safe partial-use state to fall back to.
@MainActor
final class VersionGateState: ObservableObject {
    static let shared = VersionGateState()

    @Published private(set) var isBlocked = false
    @Published private(set) var requiredVersion: String?

    private init() {}

    func activate(requiredVersion: String) {
        isBlocked = true
        self.requiredVersion = requiredVersion
    }

    /// Called whenever a fresh manifest's `minVersion` no longer exceeds the
    /// running app's version — covers the server lowering it again mid-session,
    /// not just the common "already up to date" case.
    func clear() {
        isBlocked = false
        requiredVersion = nil
    }
}

enum VersionGateCheck {
    /// Compares the running app's `CFBundleShortVersionString` against the
    /// registry manifest's `minVersion` and updates `VersionGateState`
    /// accordingly. Unparseable input on either side is treated as "no gate"
    /// (fails open) — a malformed version string should never be able to lock
    /// every installed copy of the app out.
    static func check(minVersion: String?) async {
        guard let minVersion,
              let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
              let older = isVersion(current, olderThan: minVersion)
        else { return }
        if older {
            await VersionGateState.shared.activate(requiredVersion: minVersion)
        } else {
            await VersionGateState.shared.clear()
        }
    }

    /// `nil` means one or both strings weren't dot-separated integers —
    /// callers treat that as "no gate", never a fail-closed block.
    static func isVersion(_ a: String, olderThan b: String) -> Bool? {
        guard let aParts = versionComponents(a), let bParts = versionComponents(b) else { return nil }
        for i in 0..<max(aParts.count, bParts.count) {
            let av = i < aParts.count ? aParts[i] : 0
            let bv = i < bParts.count ? bParts[i] : 0
            if av != bv { return av < bv }
        }
        return false
    }

    private static func versionComponents(_ version: String) -> [Int]? {
        let parts = version.split(separator: ".").map { Int($0) }
        // `allSatisfy` on an empty array is vacuously true, so an empty or
        // all-separator string (e.g. "", ".") would otherwise slip through as
        // a valid zero-length version instead of being rejected as garbage.
        guard !parts.isEmpty, parts.allSatisfy({ $0 != nil }) else { return nil }
        return parts.map { $0! }
    }
}
