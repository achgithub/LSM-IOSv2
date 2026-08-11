import { Hono } from "hono";
import { listMgrLinks, getMgrLifecycle, listMgrGames, putMgrLifecycle, fanOutManagerTtl } from "../kv/managerIndex";
import { getPlayerLink, putPlayerLink } from "../kv/playerLinks";
import {
  CONTENT_TTL_SECONDS, LINK_CAP_GRACE_SECONDS, REVOKE_GRACE_SECONDS, UNSUBSCRIBE_GRACE_SECONDS,
  WARN_THRESHOLD_SECONDS, addDaysIso, nowIso, secondsSince,
} from "../kv/retention";
import type { ManagerLifecycleRecord } from "../kv/types";

// ── Manager lifecycle (KV design) ─────────────────────────────────────────────
//
// This is worker-api-v2's rebuild of worker-api's routes/manager.ts: tracks
// per-manager cloud data lifecycle (subscription state, abandonment
// warnings, scheduled deletion after unsubscribe) — storage moved from D1
// (manager_lifecycle) to KV, no cron.
//
// The manager_token is a client-generated UUID (stored in iOS @AppStorage),
// never tied to PII. It's the anonymous key that links round pushes and
// player links to one subscriber.
//
// Token is passed via X-Manager-Token header (not the URL path) so it stays
// out of server logs and Cloudflare access logs.
//
// Retention policy (all computed from KV TTLs + the mgr_lifecycle record —
// no cron):
//   Active:            data lives indefinitely while pushes happen ≤ ~86 days apart
//   Warned:            computed at GET /manager/status read time — no push for
//                       WARN_THRESHOLD_SECONDS; iOS shows banner
//   Abandoned delete:  content quietly expires out of KV on its own after
//                       CONTENT_TTL_SECONDS of inactivity — nothing to run
//   Unsubscribed:      iOS calls /unsubscribe → scheduledDeleteAt = now + 14d,
//                       and every reachable KV key is shortened to that same
//                       window right away (fanOutManagerTtl) — KV's own
//                       expiry deletes it, no cron required
//   Grace delete:      the shortened TTL lapsing IS the delete

export const manager = new Hono<{ Bindings: Env }>();

function now(): string { return nowIso(); }

function tokenFromHeader(c: { req: { header: (name: string) => string | undefined } }): string | null {
  return c.req.header("X-Manager-Token")?.toLowerCase() ?? null;
}

// GET /manager/status
// Returns the lifecycle state for the iOS Cloud Settings screen.
// Called when the Cloud Settings section is opened — not on every app launch.
manager.get("/status", async (c) => {
  const token = tokenFromHeader(c);
  if (!token) return c.json({ error: "missing X-Manager-Token" }, 400);
  const kv = c.env.SUBMISSIONS_KV;

  const row = await getMgrLifecycle(kv, token);
  if (!row) return c.json({ state: "not_found" });

  if (row.scheduledDeleteAt) {
    const deleteAt = new Date(row.scheduledDeleteAt);
    const daysLeft = Math.ceil((deleteAt.getTime() - Date.now()) / 86_400_000);
    return c.json({
      state: "pending_delete",
      scheduledDeleteAt: row.scheduledDeleteAt,
      daysUntilDeletion: Math.max(0, daysLeft),
    });
  }

  // "Warned" (abandoned path) — computed here from the newest updatedAt
  // across every game this manager owns (the mgr_game: index, one list()
  // call — see kv/managerIndex.ts). There's no stored warned_at to port: in
  // worker-api's D1 design that field was only ever set by a cron that was
  // never activated in production.
  const games = await listMgrGames(kv, token);
  let newestUpdatedAt: string | null = null;
  for (const { metadata } of games) {
    if (!newestUpdatedAt || metadata.updatedAt > newestUpdatedAt) newestUpdatedAt = metadata.updatedAt;
  }
  if (newestUpdatedAt && secondsSince(newestUpdatedAt) >= WARN_THRESHOLD_SECONDS) {
    return c.json({ state: "warned", warnedAt: addDaysIso(newestUpdatedAt, WARN_THRESHOLD_SECONDS / 86_400) });
  }

  return c.json({ state: "active" });
});

// POST /manager/unsubscribe
// Called by the iOS app when RevenueCat reports the cloud bundle has lapsed.
// Idempotent — safe to call multiple times; only sets scheduledDeleteAt once.
// Immediately fans the shortened TTL out to every reachable KV key (links,
// games, submissions) — KV's own expiry deletes the data once the window
// lapses, no cron required.
manager.post("/unsubscribe", async (c) => {
  const token = tokenFromHeader(c);
  if (!token) return c.json({ error: "missing X-Manager-Token" }, 400);
  const kv = c.env.SUBMISSIONS_KV;

  const ts = now();
  const deleteAt = addDaysIso(ts, 14);

  const existing = await getMgrLifecycle(kv, token);
  const record: ManagerLifecycleRecord = existing
    ? {
        ...existing,
        unsubscribedAt: existing.unsubscribedAt ?? ts,
        scheduledDeleteAt: existing.scheduledDeleteAt ?? deleteAt,
      }
    : { managerToken: token, createdAt: ts, unsubscribedAt: ts, scheduledDeleteAt: deleteAt, maxPWALinks: null, linkCapWarnedAt: null };
  await putMgrLifecycle(kv, record);

  await fanOutManagerTtl(kv, token, UNSUBSCRIBE_GRACE_SECONDS);

  return c.json({ ok: true, scheduledDeleteAt: record.scheduledDeleteAt });
});

// POST /manager/resubscribe
// Called if the manager re-subscribes within the grace period — clears the
// pending deletion and restores every KV key's TTL back to CONTENT_TTL_SECONDS
// so unsubscribe's shortened window doesn't still quietly reclaim active data.
manager.post("/resubscribe", async (c) => {
  const token = tokenFromHeader(c);
  if (!token) return c.json({ error: "missing X-Manager-Token" }, 400);
  const kv = c.env.SUBMISSIONS_KV;

  const existing = await getMgrLifecycle(kv, token);
  if (existing) {
    await putMgrLifecycle(kv, { ...existing, unsubscribedAt: null, scheduledDeleteAt: null });
    await fanOutManagerTtl(kv, token, CONTENT_TTL_SECONDS);
  }
  return c.json({ ok: true });
});

// POST /manager/entitlements
// Body: { maxPWALinks: number | null }. Called once per app launch (and on
// purchase/restore) after Entitlements.apply(tier:) resolves — the server has
// no other way to know a manager's PWA link cap, since tier/entitlement is a
// client-side (StoreKit) concept.
//
// Over-cap LRU-revoke, inlined — evaluated synchronously right here instead
// of by a daily cron, since this is the only place maxPWALinks changes. Same
// 14-day grace window as worker-api's (never-activated) cron design: first
// over-cap call starts the clock (linkCapWarnedAt), a later call past the
// grace revokes the least-recently-used excess links. If the manager is
// currently in an over-cap grace and this report shows them back under cap
// (e.g. they revoked links or re-upgraded), the grace is cancelled
// immediately rather than waiting out the window — same eager-cancel pattern
// as resubscribe.
manager.post("/entitlements", async (c) => {
  const token = tokenFromHeader(c);
  if (!token) return c.json({ error: "missing X-Manager-Token" }, 400);
  const kv = c.env.SUBMISSIONS_KV;

  const body = await c.req.json<{ maxPWALinks?: number | null }>().catch(() => null);
  const maxPWALinks = typeof body?.maxPWALinks === "number" ? body.maxPWALinks : null;
  const ts = now();

  const existing = await getMgrLifecycle(kv, token);
  let record: ManagerLifecycleRecord = existing
    ? { ...existing, maxPWALinks }
    : { managerToken: token, createdAt: ts, unsubscribedAt: null, scheduledDeleteAt: null, maxPWALinks, linkCapWarnedAt: null };

  if (maxPWALinks != null) {
    const links = await listMgrLinks(kv, token);
    const active = links.filter((l) => l.metadata.revoked !== true);

    if (active.length <= maxPWALinks) {
      if (record.linkCapWarnedAt) record = { ...record, linkCapWarnedAt: null };
    } else if (!record.linkCapWarnedAt) {
      record = { ...record, linkCapWarnedAt: ts };
    } else if (secondsSince(record.linkCapWarnedAt) >= LINK_CAP_GRACE_SECONDS) {
      const excess = active.length - maxPWALinks;
      // Never-used links first (lastUsedAt null), then oldest-used first —
      // matches worker-api's cron design's
      // `ORDER BY last_used_at IS NOT NULL ASC, last_used_at ASC`.
      const sorted = [...active].sort((a, b) => {
        const aUsed = a.metadata.lastUsedAt, bUsed = b.metadata.lastUsedAt;
        if (aUsed === null && bUsed !== null) return -1;
        if (aUsed !== null && bUsed === null) return 1;
        if (aUsed === null && bUsed === null) return 0;
        return (aUsed as string).localeCompare(bUsed as string);
      });
      const toRevoke = sorted.slice(0, excess);
      for (const entry of toRevoke) {
        const link = await getPlayerLink(kv, entry.token);
        if (link && !link.revokedAt) {
          link.revokedAt = ts;
          await putPlayerLink(kv, link, REVOKE_GRACE_SECONDS);
        }
      }
      record = { ...record, linkCapWarnedAt: null };
    }
  }

  await putMgrLifecycle(kv, record);
  return c.json({ ok: true });
});
