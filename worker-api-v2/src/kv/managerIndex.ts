// ── Manager → {links, games} indexes + lifecycle record ───────────────────────
// Two parallel marker-key indexes (mgr_link:, mgr_game:) replace worker-api's
// D1 `WHERE manager_token = ?` queries on player_tokens/round_pushes — each
// list()'s metadata carries everything the common lookups need (over-cap
// sweep, revoke-by-name, /manager/status warned-state) with zero extra get()
// calls. See the plan's "The hard problems, resolved" section.
//
// kv/* functions take a bare `KVNamespace` rather than the full `Env` — keeps
// this vocabulary layer typecheckable independently of Env's shape (which
// only gains the SUBMISSIONS_KV binding once wrangler.jsonc + `wrangler
// types` catch up, later in the build order) and mirrors how routes call
// these with `c.env.SUBMISSIONS_KV` explicitly.

import {
  mgrGameKey, mgrGamePrefix, mgrLinkKey, mgrLinkPrefix, mgrLifecycleKey,
  submissionPrefixForManager, tokenFromMgrLinkKey, gameTokenFromMgrGameKey,
} from "./keys";
import { MGR_LIFECYCLE_TTL_SECONDS, nowIso } from "./retention";
import type { ManagerLifecycleRecord, MgrGameMetadata, MgrLinkMetadata } from "./types";

// ─── mgr_link index ──────────────────────────────────────────────────────────

export async function putMgrLink(
  kv: KVNamespace, managerToken: string, token: string, metadata: MgrLinkMetadata, ttlSeconds: number,
): Promise<void> {
  await kv.put(mgrLinkKey(managerToken, token), "", { metadata, expirationTtl: ttlSeconds });
}

export async function deleteMgrLink(kv: KVNamespace, managerToken: string, token: string): Promise<void> {
  await kv.delete(mgrLinkKey(managerToken, token));
}

export interface MgrLinkEntry { token: string; metadata: MgrLinkMetadata }

/** Every player-link index entry for one manager — the whole point of the mgr_link: index (revoke-by-name, over-cap sweep, link counts). */
export async function listMgrLinks(kv: KVNamespace, managerToken: string): Promise<MgrLinkEntry[]> {
  const out: MgrLinkEntry[] = [];
  let cursor: string | undefined;
  do {
    const page = await kv.list<MgrLinkMetadata>({ prefix: mgrLinkPrefix(managerToken), cursor });
    for (const k of page.keys) {
      const token = tokenFromMgrLinkKey(k.name);
      if (token && k.metadata) out.push({ token, metadata: k.metadata });
    }
    cursor = page.list_complete ? undefined : page.cursor;
  } while (cursor);
  return out;
}

// ─── mgr_game index ──────────────────────────────────────────────────────────

export async function putMgrGame(
  kv: KVNamespace, managerToken: string, gameToken: string, metadata: MgrGameMetadata, ttlSeconds: number,
): Promise<void> {
  await kv.put(mgrGameKey(managerToken, gameToken), "", { metadata, expirationTtl: ttlSeconds });
}

export async function deleteMgrGame(kv: KVNamespace, managerToken: string, gameToken: string): Promise<void> {
  await kv.delete(mgrGameKey(managerToken, gameToken));
}

export interface MgrGameEntry { gameToken: string; metadata: MgrGameMetadata }

export async function listMgrGames(kv: KVNamespace, managerToken: string): Promise<MgrGameEntry[]> {
  const out: MgrGameEntry[] = [];
  let cursor: string | undefined;
  do {
    const page = await kv.list<MgrGameMetadata>({ prefix: mgrGamePrefix(managerToken), cursor });
    for (const k of page.keys) {
      const gameToken = gameTokenFromMgrGameKey(k.name);
      if (gameToken && k.metadata) out.push({ gameToken, metadata: k.metadata });
    }
    cursor = page.list_complete ? undefined : page.cursor;
  } while (cursor);
  return out;
}

// ─── mgr_lifecycle ───────────────────────────────────────────────────────────

export async function getMgrLifecycle(kv: KVNamespace, managerToken: string): Promise<ManagerLifecycleRecord | null> {
  const raw = await kv.get(mgrLifecycleKey(managerToken));
  return raw ? (JSON.parse(raw) as ManagerLifecycleRecord) : null;
}

export async function putMgrLifecycle(kv: KVNamespace, record: ManagerLifecycleRecord): Promise<void> {
  await kv.put(mgrLifecycleKey(record.managerToken), JSON.stringify(record), {
    expirationTtl: MGR_LIFECYCLE_TTL_SECONDS,
  });
}

/**
 * Upsert-if-missing, field-by-field — replaces D1's `INSERT OR IGNORE`.
 * Critically a *merge*, not a read-then-blind-write of a fresh record: KV's
 * up-to-60s stale-read window means a get() done concurrently with e.g.
 * POST /manager/unsubscribe could see a stale `null` and, if this wrote a
 * brand-new record, silently wipe unsubscribedAt/scheduledDeleteAt/
 * maxPWALinks. Every push/mint call goes through this, so it only ever fills
 * in fields it owns (createdAt) and never touches fields it doesn't.
 */
export async function ensureManagerLifecycle(kv: KVNamespace, managerToken: string): Promise<void> {
  const existing = await getMgrLifecycle(kv, managerToken);
  if (existing) return; // already present — nothing this call owns needs updating
  await putMgrLifecycle(kv, {
    managerToken,
    createdAt: nowIso(),
    unsubscribedAt: null,
    scheduledDeleteAt: null,
    maxPWALinks: null,
    linkCapWarnedAt: null,
  });
}

// ─── Unsubscribe TTL fan-out ─────────────────────────────────────────────────
//
// Unsubscribe's 14-day delete is not TTL-native by itself (content TTL is
// refreshed-on-touch) — walk every key reachable from this manager's two
// indexes plus its submission tree and shorten each to `ttlSeconds`.
// /resubscribe calls this again with CONTENT_TTL_SECONDS to reverse it.
// Bounded fan-out (≤140-ish links, plus their games/submissions) — no cron,
// KV's own expiry does the deleting once the shortened TTL lapses.

export async function fanOutManagerTtl(kv: KVNamespace, managerToken: string, ttlSeconds: number): Promise<void> {
  const links = await listMgrLinks(kv, managerToken);
  for (const { token, metadata } of links) {
    const raw = await kv.get(`player_link:${token}`);
    if (raw) await kv.put(`player_link:${token}`, raw, { expirationTtl: ttlSeconds });
    await putMgrLink(kv, managerToken, token, metadata, ttlSeconds);
  }

  const games = await listMgrGames(kv, managerToken);
  for (const { gameToken, metadata } of games) {
    const raw = await kv.get(`round_push:${gameToken}`);
    if (raw) await kv.put(`round_push:${gameToken}`, raw, { expirationTtl: ttlSeconds });
    await putMgrGame(kv, managerToken, gameToken, metadata, ttlSeconds);
  }

  // Submissions are directly reachable in one more list() thanks to the
  // managerToken-first prefix (plan decision #4) — worth doing since this is
  // exactly the data a 14-day delete promise is about.
  let cursor: string | undefined;
  do {
    const page = await kv.list({ prefix: submissionPrefixForManager(managerToken), cursor });
    for (const k of page.keys) {
      const raw = await kv.get(k.name);
      if (raw && k.metadata) await kv.put(k.name, raw, { metadata: k.metadata, expirationTtl: ttlSeconds });
    }
    cursor = page.list_complete ? undefined : page.cursor;
  } while (cursor);
}
