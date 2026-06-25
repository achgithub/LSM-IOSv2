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
// NOT attest-gated (Andrew, 2026-06-25): same as v1 — attestation isn't
// enforced anywhere live yet, deferred until App Store release rather than
// added piecemeal per-route ahead of that. The restore-code uuid being
// unguessable is this route's actual access control, same model as
// `submission_tokens` elsewhere. Re-add `import { requireAttestation } from
// "../middleware/attest"` + `backup.use("*", requireAttestation)` at release.
export const backup = new Hono<{ Bindings: Env }>();

const keyFor = (id: string) => `backups/${id}.json`;

// PUT /backup/:id — body is the app's BackupBundle JSON. Overwrites any
// existing blob at this id (the manager just re-backs-up onto the same code).
backup.put("/:id", async (c) => {
  // Lowercase defensively (see worker/src/routes/publish.ts for why: Swift's
  // UUID.uuidString is uppercase, R2 keys are case-sensitive). Self-consistent
  // today since PUT/GET both come from the same Swift-generated id, but
  // normalize anyway so it can never depend on that staying true.
  const id = c.req.param("id").toLowerCase();
  const body = await c.req.text();
  if (!body) return c.json({ error: "empty body" }, 400);
  await c.env.BACKUPS.put(keyFor(id), body, {
    httpMetadata: { contentType: "application/json" },
  });
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
