import Foundation

/// The D1 shard this manager's data lives on — resolved once by the
/// authority (first App Attest register, refreshed on every assert/JWT
/// mint) and cached here so every manager-facing request can declare it
/// explicitly via `X-Shard-Id` instead of the server having to look it up.
/// See worker-api's `shardRouter.ts` for the server side of this.
///
/// UserDefaults, not Keychain — this is routing metadata, not a credential.
/// Unlike `ManagerToken` there's nothing sensitive to protect, and losing it
/// (reinstall, cache clear) just means the next request falls back to the
/// server's own resolution rather than failing — see the fallback path in
/// `shardRouter.ts`.
///
/// `nonisolated` for the same reason as `ManagerToken`: read/written from
/// background actors (`AppAttestService`, the various Cloud clients), never
/// tied to the main thread.
nonisolated enum ShardID {
    private static let defaultsKey = "cloudShardId"

    static var current: String? {
        get { UserDefaults.standard.string(forKey: defaultsKey) }
        set { UserDefaults.standard.set(newValue, forKey: defaultsKey) }
    }
}
