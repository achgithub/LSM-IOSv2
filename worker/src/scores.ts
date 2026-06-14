// KV score cache — versioned counter-pair pattern (spec §4.2 / §10.2).
//
// Each tier keeps a call/refresh counter pair plus a timestamp:
//   scores:<tier>          fixture scores JSON
//   scores:<tier>:call     integer, bumped by the first caller that sees staleness
//   scores:<tier>:refresh  integer, set equal to call once the upstream write lands
//   scores:<tier>:ts       ISO8601, when call was last bumped (the time gate)
//
// State machine:
//   call == refresh, fresh  -> serve cache, no upstream call
//   call == refresh, stale  -> bump call, serve stale now, refresh in background
//   call >  refresh         -> refresh in flight; serve stale now, poll in background
//
// The two tiers are fully independent. Stale data is ALWAYS served immediately;
// the user never waits on upstream. Result: ~1 upstream call per TTL window
// regardless of concurrent users.

import type { ScoreEntry, Tier } from "./types";

// Minimal structural type — we only need waitUntil, so we don't couple to the
// exact ExecutionContext shape (which differs between Hono and the workerd
// runtime types). Both Hono's c.executionCtx and the global ctx satisfy this.
interface BackgroundCtx {
  waitUntil(promise: Promise<unknown>): void;
}

const MAX_RETRIES = 5; // 5 × 1s = 5s max background poll

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function keys(tier: Tier) {
  return {
    data: `scores:${tier}`,
    call: `scores:${tier}:call`,
    refresh: `scores:${tier}:refresh`,
    ts: `scores:${tier}:ts`,
  };
}

function parseInt0(v: string | null): number {
  const n = parseInt(v ?? "0", 10);
  return Number.isFinite(n) ? n : 0;
}

/**
 * Resolve scores for a tier. Returns cached data immediately and uses
 * `waitUntil` for any background refresh/poll so the response never blocks.
 */
export async function getScores(
  kv: KVNamespace,
  tier: Tier,
  ttlMs: number,
  fetchUpstream: () => Promise<ScoreEntry[]>,
  ctx: BackgroundCtx,
): Promise<ScoreEntry[]> {
  const k = keys(tier);

  const [cached, callStr, refreshStr, tsStr] = await Promise.all([
    kv.get(k.data),
    kv.get(k.call),
    kv.get(k.refresh),
    kv.get(k.ts),
  ]);

  const call = parseInt0(callStr);
  const refresh = parseInt0(refreshStr);
  const ts = tsStr ? new Date(tsStr).getTime() : 0;
  const stale = Date.now() - ts >= ttlMs;

  if (call === refresh && stale) {
    // This Worker claims the refresh — bump call, then refresh in background.
    // (Residual race per spec §10.2: two Workers can both claim; worst case is
    // one duplicate upstream call. Correctness is unaffected.)
    await kv.put(k.call, String(call + 1));
    await kv.put(k.ts, new Date().toISOString());
    ctx.waitUntil(doRefresh(kv, tier, call + 1, fetchUpstream));
  } else if (call > refresh) {
    // Refresh already in flight elsewhere — background housekeeping only.
    ctx.waitUntil(pollUntilFresh(kv, tier, call));
  }
  // call === refresh && !stale -> cache fresh, serve directly.

  return cached ? (JSON.parse(cached) as ScoreEntry[]) : [];
}

async function doRefresh(
  kv: KVNamespace,
  tier: Tier,
  expectedCall: number,
  fetchUpstream: () => Promise<ScoreEntry[]>,
): Promise<void> {
  const k = keys(tier);
  try {
    const data = await fetchUpstream();
    await kv.put(k.data, JSON.stringify(data));
    await kv.put(k.refresh, String(expectedCall));
  } catch (err) {
    // Leave refresh < call so a later request retries. Stale data already served.
    console.error(JSON.stringify({ msg: "score refresh failed", tier, error: String(err) }));
  }
}

async function pollUntilFresh(kv: KVNamespace, tier: Tier, expectedCall: number): Promise<void> {
  const k = keys(tier);
  for (let i = 0; i < MAX_RETRIES; i++) {
    await sleep(1000);
    const refresh = parseInt0(await kv.get(k.refresh));
    if (refresh >= expectedCall) return; // fresh — next user request gets it
  }
  // Timed out — stale was already served, next request will retry.
}

/**
 * Cron cache-warm: write fresh data and reset the counter pair to (0,0).
 * Called inside the maintenance window so the first user of the day gets fresh
 * data with zero upstream calls and no accumulated integer drift (§10.3).
 */
export async function warmCache(kv: KVNamespace, tier: Tier, data: ScoreEntry[]): Promise<void> {
  const k = keys(tier);
  await kv.put(k.data, JSON.stringify(data));
  await kv.put(k.call, "0");
  await kv.put(k.refresh, "0");
  await kv.put(k.ts, new Date().toISOString());
}
