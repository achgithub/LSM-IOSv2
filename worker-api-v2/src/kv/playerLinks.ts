// ── player_link:{token} + its mgr_link: index entry ───────────────────────────
// Replaces player_tokens (+ its manager_token index) — enrollment (the old
// game_enrollments join table) lives inside PlayerLinkRecord.games instead,
// Clubroom2's `leagues[]` pattern.

import { mgrLinkKey, playerLinkKey } from "./keys";
import { ensureManagerLifecycle, putMgrLink } from "./managerIndex";
import { CONTENT_TTL_SECONDS, REVOKE_GRACE_SECONDS, nowIso } from "./retention";
import type { PlayerLinkRecord } from "./types";

export async function getPlayerLink(kv: KVNamespace, token: string): Promise<PlayerLinkRecord | null> {
  const raw = await kv.get(playerLinkKey(token));
  return raw ? (JSON.parse(raw) as PlayerLinkRecord) : null;
}

export async function putPlayerLink(kv: KVNamespace, record: PlayerLinkRecord, ttlSeconds: number): Promise<void> {
  await kv.put(playerLinkKey(record.token), JSON.stringify(record), { expirationTtl: ttlSeconds });
  if (record.managerToken) {
    await putMgrLink(kv, record.managerToken, record.token, {
      playerName: record.playerName,
      lastUsedAt: record.lastUsedAt,
      revoked: record.revokedAt !== null,
    }, ttlSeconds);
  }
}

/**
 * POST /links — mint is unconditional (plan decision #2: no player_name
 * uniqueness check; revoke-by-name is the self-heal path for a manager who
 * lost its local record of a token).
 */
export async function mintPlayerLink(
  kv: KVNamespace, args: { playerName: string; managerToken: string | null; managerName: string | null },
): Promise<PlayerLinkRecord> {
  const record: PlayerLinkRecord = {
    token: crypto.randomUUID().toLowerCase(),
    playerName: args.playerName,
    managerToken: args.managerToken,
    managerName: args.managerName,
    createdAt: nowIso(),
    revokedAt: null,
    lastUsedAt: null,
    games: [],
  };
  await putPlayerLink(kv, record, CONTENT_TTL_SECONDS);
  if (args.managerToken) await ensureManagerLifecycle(kv, args.managerToken);
  return record;
}

/** POST /links/:token/revoke — false if the token doesn't exist or is already revoked. */
export async function revokePlayerLink(kv: KVNamespace, token: string): Promise<boolean> {
  const record = await getPlayerLink(kv, token);
  if (!record || record.revokedAt) return false;
  record.revokedAt = nowIso();
  await putPlayerLink(kv, record, REVOKE_GRACE_SECONDS);
  return true;
}

/**
 * POST /links/revoke-by-name — scoped to the caller's own managerToken via
 * the mgr_link: index (list, not a full-table scan) so a manager can only
 * revoke a link minted under that same managerToken.
 */
export async function revokePlayerLinkByName(kv: KVNamespace, managerToken: string, playerName: string): Promise<boolean> {
  const raw = await kv.list<{ playerName: string; revoked: boolean }>({ prefix: mgrLinkKey(managerToken, "") });
  for (const k of raw.keys) {
    if (k.metadata?.playerName === playerName && k.metadata.revoked !== true) {
      const token = k.name.slice(mgrLinkKey(managerToken, "").length);
      const record = await getPlayerLink(kv, token);
      if (!record || record.revokedAt) continue;
      record.revokedAt = nowIso();
      await putPlayerLink(kv, record, REVOKE_GRACE_SECONDS);
      return true;
    }
  }
  return false;
}

/**
 * GET /s/:token — looks up a player link and, if found and not revoked,
 * refreshes its TTL (and its mgr_link: index entry's lastUsedAt) — "reset on
 * every touch", same as Clubroom2's touchPlayerLink. Returns the record
 * as-is (still populated) for a revoked link — the caller distinguishes
 * "revoked" from "not found" itself.
 */
export async function touchPlayerLink(kv: KVNamespace, token: string): Promise<PlayerLinkRecord | null> {
  const record = await getPlayerLink(kv, token);
  if (!record) return null;
  if (record.revokedAt) return record;
  record.lastUsedAt = nowIso();
  await putPlayerLink(kv, record, CONTENT_TTL_SECONDS);
  return record;
}
