import { Hono } from "hono";

// ── Manager lifecycle (Phase 6) ───────────────────────────────────────────────
//
// Tracks per-manager cloud data lifecycle: subscription state, abandonment
// warnings, and scheduled deletion after unsubscribe.
//
// The manager_token is a client-generated UUID (stored in iOS @AppStorage),
// never tied to PII. It's the anonymous key that links round_pushes,
// player_tokens, and manager_backups to one subscriber.
//
// Retention policy:
//   Active:            data lives indefinitely while pushes happen ≤ 60 days apart
//   Warned:            no push for 45 days → warned_at set; iOS shows banner
//   Abandoned delete:  no push for 60 days → cron deletes all data
//   Unsubscribed:      iOS calls /unsubscribe → scheduled_delete_at = now + 14d
//   Grace delete:      cron deletes when scheduled_delete_at has passed

export const manager = new Hono<{ Bindings: Env }>();

function now(): string { return new Date().toISOString(); }

function addDays(date: string, days: number): string {
  const d = new Date(date);
  d.setDate(d.getDate() + days);
  return d.toISOString();
}

// GET /manager/:token/status
// Returns the lifecycle state for the iOS Cloud Settings screen.
// Called when the Cloud Settings section is opened — not on every app launch.
manager.get("/:token/status", async (c) => {
  const token = c.req.param("token").toLowerCase();

  const row = await c.env.DB.prepare(
    `SELECT manager_token, created_at, unsubscribed_at, scheduled_delete_at
     FROM manager_lifecycle WHERE manager_token = ?`
  ).bind(token).first<any>();

  if (!row) return c.json({ state: "not_found" });

  if (row.scheduled_delete_at) {
    const deleteAt = new Date(row.scheduled_delete_at);
    const daysLeft = Math.ceil((deleteAt.getTime() - Date.now()) / 86_400_000);
    return c.json({
      state: "pending_delete",
      scheduledDeleteAt: row.scheduled_delete_at,
      daysUntilDeletion: Math.max(0, daysLeft),
    });
  }

  // Check if they have been warned (abandoned path)
  const warnedPush = await c.env.DB.prepare(
    `SELECT warned_at FROM round_pushes WHERE manager_token = ? AND warned_at IS NOT NULL LIMIT 1`
  ).bind(token).first<any>();

  if (warnedPush) {
    return c.json({ state: "warned", warnedAt: warnedPush.warned_at });
  }

  return c.json({ state: "active" });
});

// POST /manager/:token/unsubscribe
// Called by the iOS app when RevenueCat reports the cloud bundle has lapsed.
// Idempotent — safe to call multiple times; only sets scheduled_delete_at once.
manager.post("/:token/unsubscribe", async (c) => {
  const token = c.req.param("token").toLowerCase();
  const ts = now();
  const deleteAt = addDays(ts, 14);

  // Upsert lifecycle row, only setting scheduled_delete_at if not already set.
  await c.env.DB.prepare(
    `INSERT INTO manager_lifecycle (manager_token, created_at, unsubscribed_at, scheduled_delete_at)
     VALUES (?, ?, ?, ?)
     ON CONFLICT (manager_token) DO UPDATE SET
       unsubscribed_at    = COALESCE(manager_lifecycle.unsubscribed_at, excluded.unsubscribed_at),
       scheduled_delete_at = COALESCE(manager_lifecycle.scheduled_delete_at, excluded.scheduled_delete_at)`
  ).bind(token, ts, ts, deleteAt).run();

  return c.json({ ok: true, scheduledDeleteAt: deleteAt });
});

// POST /manager/:token/resubscribe
// Called if the manager re-subscribes within the grace period — clears the
// pending deletion so the cron doesn't remove active data.
manager.post("/:token/resubscribe", async (c) => {
  const token = c.req.param("token").toLowerCase();
  await c.env.DB.prepare(
    `UPDATE manager_lifecycle
     SET unsubscribed_at = NULL, scheduled_delete_at = NULL
     WHERE manager_token = ?`
  ).bind(token).run();
  return c.json({ ok: true });
});
