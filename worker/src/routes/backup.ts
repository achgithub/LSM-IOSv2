import { Hono } from "hono";

// ── Cloud Backup (Phase 2) ────────────────────────────────────────────────────
// One pay-gated feature (entitlement check is client-side, same trust model as
// AdGate — see docs/lsm-v2-architecture.md §0's security note): a self-contained
// R2 blob snapshot of the manager's on-device game(s), keyed by a CLIENT-
// GENERATED uuid (the user's "restore code"). This is NOT the Layer-2 D1
// games/players/picks/predictions sync in ./games.ts — that implements the
// pre-pivot "D1 is source of truth" sketch and is unrelated/unused here. Game
// state stays on-device; the cloud only ever holds this opaque blob.
//
// Either regional shard can serve a backup (it isn't scoped to a league), so
// the BACKUPS R2 bucket is bound identically into both `uk` and `eu` envs.
//
// Attest-gated via `app.use("/backup/*", requireAttestation)` in index.ts —
// only the genuine iOS app can write or read backups.
export const backup = new Hono<{ Bindings: Env }>();

const keyFor = (id: string) => `backups/${id}.json`;

const MAX_BACKUP_BYTES = 5 * 1024 * 1024; // 5 MB — generous for any realistic game state

// PUT /backup/:id — body is the app's BackupBundle JSON. Overwrites any
// existing blob at this id (the manager just re-backs-up onto the same code).
// Send X-Manager-Token header so this backup can be attributed for lifecycle
// tracking and R2 retention (last 2 per manager).
backup.put("/:id", async (c) => {
  const id = c.req.param("id").toLowerCase();
  const managerToken = c.req.header("X-Manager-Token")?.toLowerCase() ?? null;
  const body = await c.req.text();
  if (!body) return c.json({ error: "empty body" }, 400);
  if (body.length > MAX_BACKUP_BYTES) return c.json({ error: "payload too large" }, 413);
  await c.env.BACKUPS.put(keyFor(id), body, {
    httpMetadata: { contentType: "application/json" },
  });

  if (managerToken) {
    const ts = new Date().toISOString();
    await c.env.DB.prepare(
      `INSERT OR IGNORE INTO manager_lifecycle (manager_token, created_at) VALUES (?, ?)`
    ).bind(managerToken, ts).run();
    await c.env.DB.prepare(
      `INSERT INTO manager_backups (manager_token, restore_code, backed_up_at)
       VALUES (?, ?, ?)
       ON CONFLICT (manager_token, restore_code) DO UPDATE SET backed_up_at = excluded.backed_up_at`
    ).bind(managerToken, id, ts).run();
  }

  return c.json({ ok: true });
});

// GET /backup/:id — returns the raw BackupBundle JSON, or 404 if this restore
// code has never been backed up (or was never created).
backup.get("/:id", async (c) => {
  const id = c.req.param("id").toLowerCase();
  const object = await c.env.BACKUPS.get(keyFor(id));
  if (!object) return c.json({ error: "not found" }, 404);
  return new Response(object.body, {
    headers: { "Content-Type": "application/json" },
  });
});
