import { Hono } from "hono";
import { hashPin, makeSalt, verifyPin } from "../pin";

// ── Cloud Publish ─────────────────────────────────────────────────────────────
// Manager publishes a self-contained snapshot (built on-device) to R2; a
// Cloudflare Pages Function at /l/:region/:id renders it, gated by a PIN that
// is validated HERE server-side. The region is embedded in the share link so
// the Pages Function routes to the correct authority — each regional authority
// owns its own publish_links D1 rows and all authorities share the BACKUPS R2
// bucket (key prefix "publish/").
//
// Write path (POST /publish) is JWT-gated via index.ts.
// Unlock path (POST /publish/:id/unlock) is public — called from the browser.

export const publish = new Hono<{ Bindings: Env }>();

const keyFor = (id: string) => `publish/${id}.json`;

interface PublishLinkRow {
  id: string;
  pin_salt: string;
  pin_hash: string;
  r2_key: string;
  owner_token: string | null;
  unlock_attempts: number;
  unlock_locked_until: string | null;
}

const UNLOCK_MAX_ATTEMPTS = 10;
const UNLOCK_LOCKOUT_MINUTES = 30;

// POST /publish
// Body: { id?: string, ownerToken?: string, pin: string, snapshot: <PublishSnapshot>, managerToken?: string }
// Omit `id` to mint a new link (response includes a fresh ownerToken to store
// and send back on every future republish). JWT auth on write; ownerToken is
// the ownership proof for republishing an existing link. managerToken is the
// same client-generated id used on backup/round-push calls — stored purely so
// a manager's publish links can be found and cascade-deleted on unsubscribe.
publish.post("/", async (c) => {
  const body = await c.req.json<{ id?: string; ownerToken?: string; pin?: string; snapshot?: unknown; managerToken?: string }>().catch(() => null);
  if (!body?.pin || !body.snapshot) {
    return c.json({ error: "pin and snapshot are required" }, 400);
  }
  const managerToken = body.managerToken?.toLowerCase() ?? null;

  // Lowercase always — Swift's UUID.uuidString is uppercase, server uses lowercase.
  let id = body.id?.toLowerCase();
  let ownerToken = body.ownerToken;

  if (id) {
    const existing = await c.env.DB
      .prepare("SELECT owner_token FROM publish_links WHERE id = ?1")
      .bind(id)
      .first<{ owner_token: string | null }>();
    if (!existing) return c.json({ error: "not found" }, 404);
    if (existing.owner_token == null || existing.owner_token !== ownerToken) {
      return c.json({ error: "ownership cannot be verified" }, 401);
    }
  } else {
    id = crypto.randomUUID();
    ownerToken = crypto.randomUUID();
  }

  const salt = makeSalt();
  const hash = await hashPin(body.pin, salt);
  const r2Key = keyFor(id);
  const now = new Date().toISOString();

  await c.env.BACKUPS.put(r2Key, JSON.stringify(body.snapshot), {
    httpMetadata: { contentType: "application/json" },
  });
  // Republishing clears any unlock lockout too — a manager fixing a PIN
  // problem by republishing should never stay locked out from their own fix.
  await c.env.DB
    .prepare(
      `INSERT INTO publish_links (id, pin_salt, pin_hash, r2_key, owner_key_id, owner_token, manager_token, created_at, updated_at, unlock_attempts, unlock_locked_until)
       VALUES (?1, ?2, ?3, ?4, '', ?5, ?6, ?7, ?7, 0, NULL)
       ON CONFLICT (id) DO UPDATE SET pin_salt = ?2, pin_hash = ?3, r2_key = ?4, manager_token = COALESCE(publish_links.manager_token, ?6), updated_at = ?7, unlock_attempts = 0, unlock_locked_until = NULL`,
    )
    .bind(id, salt, hash, r2Key, ownerToken, managerToken, now)
    .run();

  return c.json({ id, ownerToken, region: c.env.REGION });
});

// POST /publish/:id/unlock — PUBLIC (called from the Pages viewer in browser).
// Body: { pin: string }. Returns snapshot JSON on success; 401/429 otherwise.
publish.post("/:id/unlock", async (c) => {
  const id = c.req.param("id").toLowerCase();
  const body = await c.req.json<{ pin?: string }>().catch(() => null);
  if (!body?.pin) return c.json({ error: "pin is required" }, 400);

  const link = await c.env.DB
    .prepare("SELECT id, pin_salt, pin_hash, r2_key, unlock_attempts, unlock_locked_until FROM publish_links WHERE id = ?1")
    .bind(id)
    .first<PublishLinkRow>();
  if (!link) return c.json({ error: "not found" }, 404);

  if (link.unlock_locked_until && new Date(link.unlock_locked_until) > new Date()) {
    return c.json({ error: "too many attempts — try again later" }, 429);
  }

  if (!(await verifyPin(body.pin, link.pin_salt, link.pin_hash))) {
    const newAttempts = (link.unlock_attempts ?? 0) + 1;
    const lockedUntil = newAttempts >= UNLOCK_MAX_ATTEMPTS
      ? new Date(Date.now() + UNLOCK_LOCKOUT_MINUTES * 60_000).toISOString()
      : null;
    await c.env.DB
      .prepare("UPDATE publish_links SET unlock_attempts = ?1, unlock_locked_until = ?2 WHERE id = ?3")
      .bind(newAttempts, lockedUntil, id)
      .run();
    return lockedUntil
      ? c.json({ error: "too many attempts — try again later" }, 429)
      : c.json({ error: "invalid pin" }, 401);
  }

  await c.env.DB
    .prepare("UPDATE publish_links SET unlock_attempts = 0, unlock_locked_until = NULL WHERE id = ?1")
    .bind(id)
    .run();

  const object = await c.env.BACKUPS.get(link.r2_key);
  if (!object) return c.json({ error: "not found" }, 404);
  return new Response(object.body, { headers: { "Content-Type": "application/json" } });
});
