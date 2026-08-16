import { Hono } from "hono";
import { issueChallenge, verifyAttestation, verifyAssertion, verifyChallenge } from "../attest";
import { CHALLENGE_MAX_AGE_MS, attestBypassed, getAttestConfig, getChallengeSecret } from "../attest-config";
import { getDevice, insertDevice, updateSignCount, deleteDevice } from "../attest-store";
import { getAccountLinkByManagerToken, setActiveKeyId } from "../account-store";
import { consumePendingBind } from "../otp";
import { requireAdmin, regionSecret } from "../auth";
import { signJWT } from "../jwt";
import { resolveManagerDB, resolveKeyShardDB, pinIdentityToShard } from "../shardRouter";

function shardHeader(c: { req: { header: (name: string) => string | undefined } }): string | null {
  return c.req.header("X-Shard-Id") ?? null;
}

// ── App Attest enrolment + JWT issuance ──────────────────────────────────────
//
//   POST /attest/challenge   → { challenge }   (public, no auth)
//   POST /attest/register    → { ok }          (public, attested cert chain —
//                                              see the account-transfer guard
//                                              inside for manager_tokens with
//                                              a linked account, src/account-store.ts)
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
  let body: { keyId?: string; attestation?: string; challenge?: string; managerToken?: string };
  try { body = await c.req.json(); } catch {
    return c.json({ error: "invalid json" }, 400);
  }
  const { keyId, attestation, challenge } = body;
  if (!keyId || !attestation || !challenge) {
    return c.json({ error: "keyId, attestation and challenge are required" }, 400);
  }
  // managerToken is the same client-generated id used on backup/round-push
  // calls — stored so a manager's attested devices can be found and
  // cascade-deleted on unsubscribe, and (see the account-transfer guard
  // below) so a device recovering via email/OTP can prove it's allowed to
  // become this manager_token's active device.
  const managerToken = body.managerToken?.toLowerCase() ?? null;

  const secret = getChallengeSecret(c.env);
  if (!(await verifyChallenge(secret, challenge, CHALLENGE_MAX_AGE_MS))) {
    return c.json({ error: "invalid or expired challenge" }, 401);
  }

  try {
    // Dev bypass mirrors the one in /assert (same double gate: ATTEST_DEV_BYPASS=1
    // AND non-production APP_ATTEST_ENV) — Apple's cert chain can't be faked in
    // the Simulator, so without this, register (and everything gated behind the
    // guard below) was previously untestable outside a real device.
    const verified = attestBypassed(c.env)
      ? { publicKey: `dev-bypass:${keyId}`, signCount: 0, environment: "development" as const }
      : await verifyAttestation(attestation, keyId, challenge, getAttestConfig(c.env));

    // Account-transfer guard: if this manager_token has a linked account
    // (src/account-store.ts), only its current active_key_id — or a keyId
    // carrying a live pending-bind ticket from a just-completed
    // /account/link-device/verify — may register. Without this, a device
    // evicted by a transfer could silently re-register itself back in the
    // moment its cached JWT expired, since attestation alone (a valid key +
    // a manager_token it already knows) was never proof of *current*
    // authorization once an account exists. Not shard-routed — see
    // schema.sql's comment on accounts for why.
    if (managerToken) {
      const link = await getAccountLinkByManagerToken(c.env.DB, managerToken);
      if (link && link.activeKeyId !== keyId) {
        const pending = await consumePendingBind(c.env.FLAGS, managerToken);
        if (!pending) {
          return c.json({ error: "device not authorized — link via email first" }, 403);
        }
        await deleteDevice(c.env.DB, link.activeKeyId);
        await setActiveKeyId(c.env.DB, link.accountUuid, keyId);
      }
      // else: no linked account, or this is the account's current device
      // re-registering (e.g. reinstall) — proceed as normal, no swap needed.
    }

    // Register is the earliest point a brand-new manager's device ever
    // touches this API (it's a prerequisite for the JWT every other
    // manager-facing route requires) — resolving the shard here, before
    // anything else exists for this manager, is what lets a genuinely new
    // manager get load-balanced from their very first request. Echoed back
    // below so the client can cache it immediately.
    const { shardId, db } = await resolveManagerDB(c.env, shardHeader(c), managerToken);
    await insertDevice(db, {
      keyId,
      publicKey: verified.publicKey,
      signCount: verified.signCount,
      environment: verified.environment,
      managerToken,
    });
    // Same shard as the device row just written — free, no re-derivation.
    await pinIdentityToShard(c.env, "key", keyId, shardId);
    return c.json({ ok: true, shardId });
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

  const { shardId, db } = await resolveKeyShardDB(c.env, shardHeader(c), keyId);
  const device = await getDevice(db, keyId);
  if (!device) return c.json({ error: "device not registered" }, 403);

  try {
    const result = await verifyAssertion(
      assertion, device.publicKey, device.signCount, challenge, getAttestConfig(c.env),
    );
    await updateSignCount(db, keyId, result.signCount);
  } catch (err) {
    console.error(JSON.stringify({ msg: "assertion rejected", keyId, error: String(err) }));
    return c.json({ error: "assertion rejected" }, 403);
  }

  const privateKey = regionSecret(c.env, "JWT_PRIVATE_KEY");
  if (!privateKey) return c.json({ error: "JWT_PRIVATE_KEY not configured" }, 500);

  const issuer = `https://api.${c.env.REGION}.sportsmanager.site`;
  const token = await signJWT(privateKey, c.env.JWT_KID, issuer);
  const exp = Math.floor(Date.now() / 1000) + 900;
  // Echoed on every JWT refresh (every 15 min) — cheap self-heal for a
  // client whose cached shard id was ever lost (reinstall, cache clear).
  return c.json({ token, expiresAt: new Date(exp * 1000).toISOString(), shardId });
});

// ── Admin: device management ──────────────────────────────────────────────────
// All routes require Bearer <UK_ADMIN_TOKEN>.
// Not shard-routed — these are low-traffic ops tools, not the live customer
// path. They query env.DB (the default shard) directly; extend them to loop
// over every configured shard once a 2nd one is actually provisioned and
// this tooling needs to see across all of them.

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
