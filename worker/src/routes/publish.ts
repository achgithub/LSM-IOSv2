import { Hono } from "hono";
import { requireAttestation } from "../middleware/attest";
import { hashPin, makeSalt, verifyPin } from "../pin";

// ── Cloud Publish (Phase 2, Predictor only) ───────────────────────────────────
// The manager publishes a complete, self-contained snapshot (the app builds it
// from on-device data — see Core/Backup/PublishSnapshot.swift) to R2; a
// Cloudflare Pages site renders it at /l/<id>, gated by a PIN that's validated
// HERE, server-side (§0: "names are never in the openly-served payload" — the
// blob never leaves R2 unless the PIN checks out). Distinct from ./backup.ts
// (which has no PIN — possessing the restore code IS the credential) and from
// the unused Layer-2 games/submissions tables.
export const publish = new Hono<{ Bindings: Env; Variables: { attestKeyId?: string } }>();

const keyFor = (id: string) => `publish/${id}.json`;

interface PublishLinkRow {
  id: string;
  pin_salt: string;
  pin_hash: string;
  r2_key: string;
  owner_key_id: string;
}

// POST /publish — app-only (attest-gated). Body: { id?: string, pin: string,
// snapshot: <PublishSnapshot JSON> }. Omit `id` to mint a new link; pass the
// existing one back to republish to the same stable URL (this also lets the
// manager change the PIN, since a fresh salt+hash is written every call).
//
// Ownership: `owner_key_id` is the caller's verified App Attest key id (set
// by `requireAttestation`) — the closest thing to a principal this
// account-free app has. Republishing an EXISTING id is only allowed if the
// caller's key id matches the link's original owner; otherwise any attested
// app instance could hijack/overwrite someone else's published link just by
// guessing its uuid. A brand-new id has no prior owner, so it always succeeds.
publish.use("/", requireAttestation);
publish.post("/", async (c) => {
  const callerKeyId = c.get("attestKeyId");
  if (!callerKeyId) return c.json({ error: "attestation required" }, 401);

  const body = await c.req.json<{ id?: string; pin?: string; snapshot?: unknown }>().catch(() => null);
  if (!body?.pin || !body.snapshot) {
    return c.json({ error: "pin and snapshot are required" }, 400);
  }

  let id = body.id;
  if (id) {
    const existing = await c.env.DB
      .prepare("SELECT owner_key_id FROM publish_links WHERE id = ?1")
      .bind(id)
      .first<{ owner_key_id: string }>();
    if (existing && existing.owner_key_id !== callerKeyId) {
      return c.json({ error: "not the owner of this link" }, 403);
    }
  } else {
    id = crypto.randomUUID();
  }

  const salt = makeSalt();
  const hash = await hashPin(body.pin, salt);
  const r2Key = keyFor(id);
  const now = new Date().toISOString();

  await c.env.BACKUPS.put(r2Key, JSON.stringify(body.snapshot), {
    httpMetadata: { contentType: "application/json" },
  });
  await c.env.DB
    .prepare(
      `INSERT INTO publish_links (id, pin_salt, pin_hash, r2_key, owner_key_id, created_at, updated_at)
       VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?6)
       ON CONFLICT (id) DO UPDATE SET pin_salt = ?2, pin_hash = ?3, r2_key = ?4, updated_at = ?6`,
    )
    .bind(id, salt, hash, r2Key, callerKeyId, now)
    .run();

  return c.json({ id });
});

// POST /publish/:id/unlock — PUBLIC (no attest: called by the Pages page
// itself, not the app). Body: { pin: string }. Returns the snapshot JSON only
// if the PIN matches; otherwise 401. This is the one place the blob is ever
// served to a viewer.
publish.post("/:id/unlock", async (c) => {
  const id = c.req.param("id");
  const body = await c.req.json<{ pin?: string }>().catch(() => null);
  if (!body?.pin) return c.json({ error: "pin is required" }, 400);

  const link = await c.env.DB
    .prepare("SELECT id, pin_salt, pin_hash, r2_key FROM publish_links WHERE id = ?1")
    .bind(id)
    .first<PublishLinkRow>();
  if (!link) return c.json({ error: "not found" }, 404);

  if (!(await verifyPin(body.pin, link.pin_salt, link.pin_hash))) {
    return c.json({ error: "invalid pin" }, 401);
  }

  const object = await c.env.BACKUPS.get(link.r2_key);
  if (!object) return c.json({ error: "not found" }, 404);
  return new Response(object.body, { headers: { "Content-Type": "application/json" } });
});
