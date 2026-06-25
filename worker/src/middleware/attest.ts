// Hono middleware that requires a valid App Attest assertion on the data routes
// (/fixtures /scores /standings /teams). This is what turns the open proxy into
// one only the genuine iOS app can reach — protecting the licensed feed.
//
// The client sends, per request (or per session, reusing a fresh challenge):
//   X-Attest-Key-Id      base64 keyId of its attested Secure-Enclave key
//   X-Attest-Challenge   the challenge string it signed (issued by /attest/challenge)
//   X-Attest-Assertion   base64 CBOR assertion over that challenge
//
// Fails closed: any missing header, bad challenge, unknown device, bad signature
// or non-advancing counter → rejected. The only open path is the dev bypass,
// which can exist solely in local .dev.vars (see attest-config.ts).

import type { Context, Next } from "hono";
import { verifyAssertion, verifyChallenge } from "../attest";
import {
  CHALLENGE_MAX_AGE_MS,
  attestBypassed,
  getAttestConfig,
  getChallengeSecret,
} from "../attest-config";
import { getDevice, updateSignCount } from "../attest-store";

export async function requireAttestation(
  c: Context<{ Bindings: Env; Variables: { attestKeyId?: string } }>,
  next: Next,
) {
  if (attestBypassed(c.env)) {
    c.set("attestKeyId", "dev-bypass");
    return next();
  }

  const keyId = c.req.header("X-Attest-Key-Id");
  const challenge = c.req.header("X-Attest-Challenge");
  const assertion = c.req.header("X-Attest-Assertion");
  if (!keyId || !challenge || !assertion) {
    return c.json({ error: "attestation required" }, 401);
  }

  const secret = getChallengeSecret(c.env);
  if (!(await verifyChallenge(secret, challenge, CHALLENGE_MAX_AGE_MS))) {
    return c.json({ error: "invalid or expired challenge" }, 401);
  }

  const device = await getDevice(c.env.DB, keyId);
  if (!device) {
    // Unknown key — client must run /attest/register first.
    return c.json({ error: "device not registered" }, 403);
  }

  try {
    const result = await verifyAssertion(
      assertion,
      device.publicKey,
      device.signCount,
      challenge,
      getAttestConfig(c.env),
    );
    await updateSignCount(c.env.DB, keyId, result.signCount);
  } catch (err) {
    console.error(JSON.stringify({ msg: "assertion rejected", error: String(err) }));
    return c.json({ error: "assertion rejected" }, 403);
  }

  // The verified per-device key id — the closest thing to a "principal" this
  // app has (no accounts). Routes that need to scope a write to "whoever
  // created this" (e.g. Cloud Publish ownership) read it back via this key.
  c.set("attestKeyId", keyId);

  return next();
}
