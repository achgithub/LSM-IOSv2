// ── Shard router ──────────────────────────────────────────────────────────
//
// Client-explicit shard routing: a manager's device resolves its shard ONCE
// (at first App Attest registration) and caches it, then sends it explicitly
// as the X-Shard-Id header on every manager-facing request from then on —
// the server just trusts a recognized value and binds straight to that D1
// database. No lookup, no KV read, on the normal hot path. Player links and
// the PWA the manager shares carry the same header forward automatically.
//
// The KV-backed fallback below is only reached when no valid X-Shard-Id
// arrives — an app build older than this feature, or an identity that's
// never resolved before. It exists for two reasons:
//   1. Every current customer already has rows on the one shard that's
//      existed until now. The fallback's job on first contact is to
//      *confirm* that and pin it permanently — never to guess, never to
//      place existing data somewhere it isn't.
//   2. A genuinely new manager gets load-balanced across shards once there's
//      more than one, so no shard grows unbounded.
//
// Today there is exactly one shard (lsm-api-uk-db) — every function below
// degrades to a same-shard, zero-I/O return. Adding shard #2:
//   1. Provision the D1 database + add its binding to wrangler.jsonc (e.g. DB2)
//   2. Add its id to SHARD_IDS and a case to shardDB() below
//   3. Adjust WATERMARK_ROWS if the default doesn't fit
// No other code changes needed — every route already resolves through here.

const DEFAULT_SHARD_ID = "uk1";

// round_pushes rows ≈ games (one row per game_token) — the dominant per-game
// write cost; see the sync architecture doc's headroom math (~37k games/10GB
// shard). Generous on purpose: this is "stop taking new managers," not a
// hard capacity ceiling — existing managers on a shard past this line are
// completely unaffected.
const WATERMARK_ROWS = 30_000;

const SHARD_IDS = [DEFAULT_SHARD_ID] as const;
type ShardId = (typeof SHARD_IDS)[number];

function shardDB(env: Env, id: ShardId): D1Database {
  switch (id) {
    case "uk1": return env.DB;
    // case "uk2": return env.DB2;  ← add here when a 2nd shard is provisioned
  }
}

function isKnownShard(id: string): id is ShardId {
  return (SHARD_IDS as readonly string[]).includes(id);
}

interface RouterRecord {
  shardId: ShardId;
  assignedAt: string;
}

const ROUTER_PREFIX = "router:";

/// Trusts an explicit client-supplied shard id if it names a real, currently
/// configured shard — zero I/O either way. Returns null for anything absent
/// or unrecognized (including a shard that's since been decommissioned) so
/// the caller runs the fallback instead of erroring or misrouting.
export function shardFromHeader(env: Env, headerValue: string | undefined | null): D1Database | null {
  if (!headerValue || !isKnownShard(headerValue)) return null;
  return shardDB(env, headerValue);
}

/// The one fallback resolver behind resolveManagerShard/TokenShard/KeyShard
/// below — same shape for all three identity kinds, just a different KV key
/// and a different "does this identity already have data here" check.
async function resolveIdentityShard(
  env: Env, kvKey: string, hasExistingData: (db: D1Database) => Promise<boolean>
): Promise<{ shardId: ShardId; db: D1Database }> {
  const cached = await env.FLAGS.get(kvKey);
  if (cached) {
    const record = JSON.parse(cached) as RouterRecord;
    if (isKnownShard(record.shardId)) return { shardId: record.shardId, db: shardDB(env, record.shardId) };
    // Recorded shard no longer configured — fall through and reassign.
  }

  if (SHARD_IDS.length === 1) {
    // Nothing to disambiguate — every identity, existing or new, belongs
    // here. Deliberately no KV write: with one shard there's nothing a
    // record could ever resolve differently, so writing one now would only
    // be dead weight to clean up later.
    return { shardId: DEFAULT_SHARD_ID, db: shardDB(env, DEFAULT_SHARD_ID) };
  }

  // Live-customer safety: this identity may already have data on the
  // original shard from before routing existed — pin it there permanently
  // rather than risk the assignment step placing it somewhere it isn't.
  if (await hasExistingData(shardDB(env, DEFAULT_SHARD_ID))) {
    await env.FLAGS.put(kvKey, JSON.stringify(
      { shardId: DEFAULT_SHARD_ID, assignedAt: new Date().toISOString() } satisfies RouterRecord
    ));
    return { shardId: DEFAULT_SHARD_ID, db: shardDB(env, DEFAULT_SHARD_ID) };
  }

  // Genuinely new — assign the lowest-occupancy shard under watermark.
  const counts = await Promise.all(SHARD_IDS.map(async (id) => {
    const row = await shardDB(env, id).prepare(`SELECT COUNT(*) AS n FROM round_pushes`).first<{ n: number }>();
    return { id, count: row?.n ?? 0 };
  }));
  const eligible = counts.filter((c) => c.count < WATERMARK_ROWS);
  // Every shard over watermark: degrade to least-bad rather than fail
  // outright — a manager still needs somewhere to land.
  const pool = eligible.length > 0 ? eligible : counts;
  pool.sort((a, b) => a.count - b.count);
  // pool is never empty — it's derived from SHARD_IDS, which always has at
  // least DEFAULT_SHARD_ID.
  const chosen = pool[0]!.id;

  await env.FLAGS.put(kvKey, JSON.stringify(
    { shardId: chosen, assignedAt: new Date().toISOString() } satisfies RouterRecord
  ));
  return { shardId: chosen, db: shardDB(env, chosen) };
}

export async function resolveManagerShard(
  env: Env, managerToken: string
): Promise<{ shardId: ShardId; db: D1Database }> {
  return resolveIdentityShard(env, `${ROUTER_PREFIX}${managerToken}`, async (db) =>
    Boolean(await db.prepare(`SELECT 1 FROM manager_lifecycle WHERE manager_token = ?`).bind(managerToken).first())
  );
}

async function resolveTokenShard(env: Env, token: string): Promise<{ shardId: ShardId; db: D1Database }> {
  return resolveIdentityShard(env, `${ROUTER_PREFIX}token:${token}`, async (db) =>
    Boolean(await db.prepare(`SELECT 1 FROM player_tokens WHERE token = ?`).bind(token).first())
  );
}

async function resolveKeyShard(env: Env, keyId: string): Promise<{ shardId: ShardId; db: D1Database }> {
  return resolveIdentityShard(env, `${ROUTER_PREFIX}key:${keyId}`, async (db) =>
    Boolean(await db.prepare(`SELECT 1 FROM attest_devices WHERE key_id = ?`).bind(keyId).first())
  );
}

function fromHeaderOrKnown(env: Env, headerShardId: string | undefined | null): { shardId: ShardId; db: D1Database } | null {
  if (!headerShardId || !isKnownShard(headerShardId)) return null;
  return { shardId: headerShardId, db: shardDB(env, headerShardId) };
}

/// Header-first resolution for every manager-identified route (mint, round
/// push, submission review, lifecycle). Falls back to resolveManagerShard
/// only when the header is missing/unrecognized. Returns `shardId` alongside
/// `db` so a caller that just minted something under this manager (a player
/// token, an attest device) can pin it to the same shard for free — no
/// re-derivation.
export async function resolveManagerDB(
  env: Env, headerShardId: string | undefined | null, managerToken: string | null
): Promise<{ shardId: ShardId; db: D1Database }> {
  const fromHeader = fromHeaderOrKnown(env, headerShardId);
  if (fromHeader) return fromHeader;
  if (!managerToken) return { shardId: DEFAULT_SHARD_ID, db: shardDB(env, DEFAULT_SHARD_ID) };
  return resolveManagerShard(env, managerToken);
}

/// Header-first resolution for player-token-only routes (/s/:token,
/// /links/:token/revoke). No manager identity available here — the fallback
/// checks/pins by token directly, same safety property as the manager path.
export async function resolveTokenDB(
  env: Env, headerShardId: string | undefined | null, token: string
): Promise<D1Database> {
  return fromHeaderOrKnown(env, headerShardId)?.db ?? (await resolveTokenShard(env, token)).db;
}

/// Header-first resolution for attest-key-only routes (/attest/assert has
/// no managerToken, only the device's keyId). Returns `shardId` too so
/// /attest/assert — hit on every JWT refresh — can echo it back, letting a
/// client whose local cache was ever cleared self-heal without a dedicated
/// resolution call.
export async function resolveKeyShardDB(
  env: Env, headerShardId: string | undefined | null, keyId: string
): Promise<{ shardId: ShardId; db: D1Database }> {
  return fromHeaderOrKnown(env, headerShardId) ?? resolveKeyShard(env, keyId);
}

/// Piggybacks a token's/key's shard onto a KV write at the moment it's
/// minted (player link) or registered (attest device) — the caller already
/// knows the shard (it just resolved the owning manager's), so this is a
/// single cheap write, not a re-derivation. No-op while there's only one
/// shard (see resolveIdentityShard's single-shard fast path above — nothing
/// a record could ever resolve differently, so don't bother writing one).
export async function pinIdentityToShard(env: Env, kvKey: "token" | "key", id: string, shardId: ShardId): Promise<void> {
  if (SHARD_IDS.length === 1) return;
  await env.FLAGS.put(`${ROUTER_PREFIX}${kvKey}:${id}`, JSON.stringify(
    { shardId, assignedAt: new Date().toISOString() } satisfies RouterRecord
  ));
}

export function defaultShardId(): ShardId {
  return DEFAULT_SHARD_ID;
}
