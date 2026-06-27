// App Attest runtime config + the dev bypass. Kept tiny and in one place so the
// "never bypass in production" contract is auditable.

import type { AttestConfig, AttestEnvironment } from "./attest";
import { regionSecret } from "./auth";

// A challenge is valid for this long after issue. The client fetches one then
// immediately makes its request, so a few minutes is ample.
export const CHALLENGE_MAX_AGE_MS = 5 * 60_000;

export function getAttestConfig(env: Env): AttestConfig {
  return {
    teamId: env.APP_ATTEST_TEAM_ID,
    bundleId: env.APP_ATTEST_BUNDLE_ID,
    environment: env.APP_ATTEST_ENV as AttestEnvironment,
  };
}

export function getChallengeSecret(env: Env): string {
  const secret = regionSecret(env, "ATTEST_CHALLENGE_KEY");
  if (!secret) throw new Error(`${env.SHARD_REGION.toUpperCase()}_ATTEST_CHALLENGE_KEY is not configured`);
  return secret;
}

/**
 * Dev-only bypass — the Worker equivalent of `#if DEBUG`. App Attest cannot run
 * in the Simulator, so local development needs an escape hatch. This is gated on
 * `ATTEST_DEV_BYPASS === "1"`, which MUST ONLY ever be set in the local, gitignored
 * `worker/.dev.vars`. It is NEVER added to wrangler.jsonc `vars` or set as a
 * secret, so it cannot exist in any deployed environment. Verify before each
 * release that no deployed env defines ATTEST_DEV_BYPASS.
 */
export function attestBypassed(env: Env): boolean {
  return env.ATTEST_DEV_BYPASS === "1";
}
