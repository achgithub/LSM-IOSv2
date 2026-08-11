// ── TTLs and shared time helpers ──────────────────────────────────────────────
// KV `expirationTtl`, refreshed on touch, is the entire retention model here —
// nothing schedules anything. Every value below is just seconds handed to a
// `put()` call; Cloudflare's own KV expiry does the deleting. (worker-api's
// D1 cron + retention.ts that this design replaces was fully built but never
// activated in production — see the plan's Context section.)

const DAY = 60 * 60 * 24;

// One shared TTL for "content" — player links, round pushes — refreshed on
// every touch (mint, push, player GET) so an actively-used game/link never
// expires, and one nobody touches ages out on its own.
export const CONTENT_TTL_SECONDS = 100 * DAY;

// Submissions are a queue, not content — not refreshed on read. ~30 days is a
// generous backstop given submissions are also pruned to the last 2 rounds on
// every push.
export const SUBMISSION_TTL_SECONDS = 30 * DAY;

// Must outlive CONTENT_TTL_SECONDS so /manager/entitlements and /manager/status
// keep working for a quiet-but-installed app whose links/games have already
// expired out of KV.
export const MGR_LIFECYCLE_TTL_SECONDS = 400 * DAY;

// Revoke doesn't delete outright — it shortens the TTL to a grace window so
// POST /links/revoke-by-name stays idempotent (a second call still finds the
// record, sees revokedAt set, and no-ops) instead of 404ing immediately.
export const REVOKE_GRACE_SECONDS = 14 * DAY;

// Unsubscribe's 14-day delete promise — matches POST /manager/unsubscribe's
// scheduledDeleteAt window today. KV TTL fan-out (routes/manager.ts) shortens
// every reachable content key to this on unsubscribe; /resubscribe restores
// CONTENT_TTL_SECONDS.
export const UNSUBSCRIBE_GRACE_SECONDS = 14 * DAY;

// Over-cap link revoke grace (a tier downgrade can drop a manager below their
// new maxPWALinks) — same 14-day pattern as unsubscribe. Evaluated inline in
// POST /manager/entitlements now instead of by a daily cron.
export const LINK_CAP_GRACE_SECONDS = 14 * DAY;

// `GET /manager/status`'s "warned" state, computed at read time (round_pushes
// .warned_at in the old D1 design was cron-only and never actually got set in
// prod) — warn once a manager's most-recently-touched game is this many
// seconds old, 14 days before the 100-day content TTL would otherwise
// quietly reclaim it.
export const WARN_THRESHOLD_SECONDS = CONTENT_TTL_SECONDS - 14 * DAY;

export function nowIso(): string {
  return new Date().toISOString();
}

export function addDaysIso(iso: string, days: number): string {
  const d = new Date(iso);
  d.setDate(d.getDate() + days);
  return d.toISOString();
}

export function secondsSince(iso: string): number {
  return (Date.now() - new Date(iso).getTime()) / 1000;
}
