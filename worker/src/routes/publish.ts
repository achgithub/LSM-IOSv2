import { Hono } from "hono";
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
  unlock_attempts: number;
  unlock_locked_until: string | null;
}

// POST /publish — attest-gated via `app.use("/publish", requireAttestation)` in
// index.ts. Body: { id?: string, ownerToken?: string, pin: string, snapshot:
// <PublishSnapshot JSON> }. Omit `id` to mint a new link — the response then
// includes a fresh `ownerToken` the app must store (on `Game`) and send back on
// every future republish of that id. `pin` is the (possibly new, e.g. on Reset
// PIN) PIN to set going forward.
//
// Ownership: a security review correctly flagged an earlier draft that used
// the 6-digit viewer PIN itself as republish proof — brute-forceable in
// seconds, turning "guess the PIN" into "steal/relock someone else's
// published link", not just "view it" (the latter is an accepted tradeoff
// per §0; the former is not). `ownerToken` is a separate, high-entropy
// (128-bit) secret, same pattern as `submission_tokens` elsewhere, minted
// once and never brute-forceable in practice. A request with an existing
// `id` but no/wrong `ownerToken` (and no matching `attestKeyId`, for when
// `requireAttestation` is wired back in at release — see
// `../middleware/attest`) is rejected outright.
publish.post("/", async (c) => {
  const callerKeyId = c.get("attestKeyId") ?? null;

  const body = await c.req.json<{ id?: string; ownerToken?: string; pin?: string; snapshot?: unknown }>().catch(() => null);
  if (!body?.pin || !body.snapshot) {
    return c.json({ error: "pin and snapshot are required" }, 400);
  }

  // Lowercase, always — `crypto.randomUUID()` mints lowercase, but Swift's
  // `UUID.uuidString` always renders UPPERCASE, and the id round-trips
  // through the client (returned here, put in the share link, sent back on
  // republish/unlock). SQLite TEXT comparison is case-sensitive, so without
  // normalizing, every iOS-originated lookup of a server-minted id silently
  // 404s. Confirmed live 2026-06-25 — the published link itself had the
  // wrong-case id baked in, so even viewers hit this.
  let id = body.id?.toLowerCase();
  let ownerToken = body.ownerToken;
  if (id) {
    const existing = await c.env.DB
      .prepare("SELECT owner_key_id, owner_token FROM publish_links WHERE id = ?1")
      .bind(id)
      .first<{ owner_key_id: string; owner_token: string | null }>();
    if (!existing) {
      return c.json({ error: "not found" }, 404);
    }
    // "" is the no-attestation sentinel (column is NOT NULL) — callerKeyId is
    // never "" itself, so this never accidentally matches an unattested row
    // against another unattested caller.
    const ownerMatches = callerKeyId != null && existing.owner_key_id === callerKeyId;
    const tokenMatches = !ownerMatches && existing.owner_token != null && ownerToken === existing.owner_token;
    if (!ownerMatches && !tokenMatches) {
      return c.json({ error: "ownership cannot be verified" }, 401);
    }
    ownerToken = existing.owner_token ?? ownerToken; // keep the existing token stable
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
  await c.env.DB
    .prepare(
      `INSERT INTO publish_links (id, pin_salt, pin_hash, r2_key, owner_key_id, owner_token, created_at, updated_at)
       VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?7)
       ON CONFLICT (id) DO UPDATE SET pin_salt = ?2, pin_hash = ?3, r2_key = ?4, updated_at = ?7`,
    )
    .bind(id, salt, hash, r2Key, callerKeyId ?? "", ownerToken, now)
    .run();

  return c.json({ id, ownerToken });
});

const UNLOCK_MAX_ATTEMPTS = 10;
const UNLOCK_LOCKOUT_MINUTES = 30;

// POST /publish/:id/unlock — PUBLIC (no attest: called by the Pages page
// itself, not the app). Rate-limited: 10 failed attempts per link triggers a
// 30-minute per-link lockout tracked in D1. Body: { pin: string }. Returns
// the snapshot JSON only if the PIN matches; otherwise 401 or 429.
// This is the one place the blob is ever served to a viewer.
publish.post("/:id/unlock", async (c) => {
  const id = c.req.param("id").toLowerCase(); // see the case-normalization note above
  const body = await c.req.json<{ pin?: string }>().catch(() => null);
  if (!body?.pin) return c.json({ error: "pin is required" }, 400);

  const link = await c.env.DB
    .prepare("SELECT id, pin_salt, pin_hash, r2_key, unlock_attempts, unlock_locked_until FROM publish_links WHERE id = ?1")
    .bind(id)
    .first<PublishLinkRow>();
  if (!link) return c.json({ error: "not found" }, 404);

  // Per-link lockout check.
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
    if (lockedUntil) {
      return c.json({ error: "too many attempts — try again later" }, 429);
    }
    return c.json({ error: "invalid pin" }, 401);
  }

  // Successful unlock — reset the attempt counter.
  await c.env.DB
    .prepare("UPDATE publish_links SET unlock_attempts = 0, unlock_locked_until = NULL WHERE id = ?1")
    .bind(id)
    .run();

  const object = await c.env.BACKUPS.get(link.r2_key);
  if (!object) return c.json({ error: "not found" }, 404);
  return new Response(object.body, { headers: { "Content-Type": "application/json" } });
});
