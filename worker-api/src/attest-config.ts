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

export function attestBypassed(env: Env): boolean {
  return env.ATTEST_DEV_BYPASS === "1";
}
