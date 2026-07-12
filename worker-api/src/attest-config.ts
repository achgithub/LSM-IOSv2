import type { AttestConfig, AttestEnvironment } from "./attest";
import { regionSecret } from "./auth";

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
  if (!secret) throw new Error(`${env.REGION.toUpperCase()}_ATTEST_CHALLENGE_KEY is not configured`);
  return secret;
}

/**
 * Dev-only bypass — App Attest cannot run in the Simulator, so local
 * development needs an escape hatch. `ATTEST_DEV_BYPASS` MUST ONLY ever be
 * set in the local, gitignored `.dev.vars` — never in wrangler.jsonc `vars`
 * or as a secret. Also requires `APP_ATTEST_ENV !== "production"` (every
 * real deployment explicitly sets this to `"production"`) as a runtime
 * refusal so a single stray var alone can no longer disable the JWT gate in
 * production (issue #7) — two independently-configured values would both
 * have to be wrong at once.
 */
export function attestBypassed(env: Env): boolean {
  return env.ATTEST_DEV_BYPASS === "1" && env.APP_ATTEST_ENV !== "production";
}
