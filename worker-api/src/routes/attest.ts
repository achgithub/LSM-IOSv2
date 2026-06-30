import { Hono } from "hono";
import { issueChallenge, verifyAttestation, verifyAssertion, verifyChallenge } from "../attest";
import { CHALLENGE_MAX_AGE_MS, attestBypassed, getAttestConfig, getChallengeSecret } from "../attest-config";
import { getDevice, insertDevice, updateSignCount } from "../attest-store";
import { requireAdmin, regionSecret } from "../auth";
import { signJWT } from "../jwt";

// ── App Attest enrolment + JWT issuance ──────────────────────────────────────
//
//   POST /attest/challenge   → { challenge }   (public, no auth)
//   POST /attest/register    → { ok }          (public, attested cert chain)
//   POST /attest/assert      → { token, expiresAt }  NEW — verifies assertion,
//                                              returns a 15-min ES256 JWT that
//                                              sports shards and this authority
//                                              accept on all protected routes.

export const attest = new Hono<{ Bindings: Env }>();

attest.post("/challenge", async (c) => {
  const challenge = await issueChallenge(getChallengeSecret(c.env));
  return c.json({ challenge });
});

attest.post("/register", async (c) => {
  let body: { keyId?: string; attestation?: string; challenge?: string };
  try { body = await c.req.json(); } catch {
    return c.json({ error: "invalid json" }, 400);
  }
  const { keyId, attestation, challenge } = body;
  if (!keyId || !attestation || !challenge) {
    return c.json({ error: "keyId, attestation and challenge are required" }, 400);
  }

  const secret = getChallengeSecret(c.env);
  if (!(await verifyChallenge(secret, challenge, CHALLENGE_MAX_AGE_MS))) {
    return c.json({ error: "invalid or expired challenge" }, 401);
  }

  try {
    const verified = await verifyAttestation(attestation, keyId, challenge, getAttestConfig(c.env));
    await insertDevice(c.env.DB, {
      keyId,
      publicKey: verified.publicKey,
      signCount: verified.signCount,
      environment: verified.environment,
    });
    return c.json({ ok: true });
  } catch (err) {
    console.error(JSON.stringify({ msg: "attestation rejected", error: String(err) }));
    return c.json({ error: "attestation rejected" }, 403);
  }
});

// POST /attest/assert
// Verifies an App Attest assertion and returns a short-lived JWT.
// The client sends the same X-Attest-* headers used on the old per-route model;
// the response JWT is then used as Bearer on all subsequent requests.
attest.post("/assert", async (c) => {
  if (attestBypassed(c.env)) {
    // Dev bypass: issue a JWT without checking assertion headers.
    const privateKey = regionSecret(c.env, "JWT_PRIVATE_KEY");
    if (!privateKey) return c.json({ error: "JWT_PRIVATE_KEY not configured" }, 500);
    const issuer = `https://api.${c.env.REGION}.sportsmanager.site`;
    const token = await signJWT(privateKey, c.env.JWT_KID, issuer);
    const exp = Math.floor(Date.now() / 1000) + 900;
    return c.json({ token, expiresAt: new Date(exp * 1000).toISOString() });
  }

  const keyId = c.req.header("X-Attest-Key-Id");
  const challenge = c.req.header("X-Attest-Challenge");
  const assertion = c.req.header("X-Attest-Assertion");
  if (!keyId || !challenge || !assertion) {
    return c.json({ error: "attestation headers required" }, 401);
  }

  const secret = getChallengeSecret(c.env);
  if (!(await verifyChallenge(secret, challenge, CHALLENGE_MAX_AGE_MS))) {
    return c.json({ error: "invalid or expired challenge" }, 401);
  }

  const device = await getDevice(c.env.DB, keyId);
  if (!device) return c.json({ error: "device not registered" }, 403);

  try {
    const result = await verifyAssertion(
      assertion, device.publicKey, device.signCount, challenge, getAttestConfig(c.env),
    );
    await updateSignCount(c.env.DB, keyId, result.signCount);
  } catch (err) {
    console.error(JSON.stringify({ msg: "assertion rejected", keyId, error: String(err) }));
    return c.json({ error: "assertion rejected" }, 403);
  }

  const privateKey = regionSecret(c.env, "JWT_PRIVATE_KEY");
  if (!privateKey) return c.json({ error: "JWT_PRIVATE_KEY not configured" }, 500);

  const issuer = `https://api.${c.env.REGION}.sportsmanager.site`;
  const token = await signJWT(privateKey, c.env.JWT_KID, issuer);
  const exp = Math.floor(Date.now() / 1000) + 900;
  return c.json({ token, expiresAt: new Date(exp * 1000).toISOString() });
});

// ── Admin: device management ──────────────────────────────────────────────────
// All routes require Bearer <UK_ADMIN_TOKEN>.

// List all registered devices.
// GET /attest/devices → { count, devices: [{ keyId, signCount, environment, createdAt }] }
attest.get("/devices", async (c) => {
  if (!requireAdmin(c.env, c.req.header("Authorization"))) {
    return c.json({ error: "unauthorized" }, 401);
  }
  const rows = await c.env.DB.prepare(
    "SELECT key_id, sign_count, environment, created_at FROM attest_devices ORDER BY created_at DESC"
  ).all<{ key_id: string; sign_count: number; environment: string; created_at: string }>();
  const devices = (rows.results ?? []).map((r) => ({
    keyId: r.key_id,
    signCount: r.sign_count,
    environment: r.environment,
    createdAt: r.created_at,
  }));
  return c.json({ count: devices.length, devices });
});

// Delete a specific device — forces the iOS client to re-attest on next request.
// DELETE /attest/devices/:keyId
attest.delete("/devices/:keyId", async (c) => {
  if (!requireAdmin(c.env, c.req.header("Authorization"))) {
    return c.json({ error: "unauthorized" }, 401);
  }
  const keyId = c.req.param("keyId");
  const result = await c.env.DB.prepare(
    "DELETE FROM attest_devices WHERE key_id = ?"
  ).bind(keyId).run();
  if (!result.meta.changes) return c.json({ error: "device not found" }, 404);
  console.log(JSON.stringify({ msg: "device deleted by admin", keyId }));
  return c.json({ ok: true, keyId });
});
