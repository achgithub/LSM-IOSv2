import { Hono } from "hono";
import { issueChallenge, verifyAttestation, verifyChallenge } from "../attest";
import { CHALLENGE_MAX_AGE_MS, getAttestConfig, getChallengeSecret } from "../attest-config";
import { insertDevice } from "../attest-store";

// App Attest enrolment endpoints (public — no assertion required, since this is
// how a client becomes trusted). Volume is capped by the zone rate-limit.
//
//   POST /attest/challenge            -> { challenge }   (opaque, HMAC-signed, ~5 min)
//   POST /attest/register { keyId, attestation, challenge } -> { ok: true }
//
// The challenge the client signs for /register must be one we issued; we then
// verify the Apple attestation and persist the device public key + counter.
export const attest = new Hono<{ Bindings: Env }>();

attest.post("/challenge", async (c) => {
  const challenge = await issueChallenge(getChallengeSecret(c.env));
  return c.json({ challenge });
});

attest.post("/register", async (c) => {
  let body: { keyId?: string; attestation?: string; challenge?: string };
  try {
    body = await c.req.json();
  } catch {
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
