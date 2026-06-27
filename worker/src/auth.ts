// Shared auth helpers. All secrets are region-prefixed (UK_ADMIN_TOKEN, etc.)
// so each shard holds its own values and can be rotated independently.

function timingSafeEqual(a: string, b: string): boolean {
  const enc = new TextEncoder();
  const ab = enc.encode(a);
  const bb = enc.encode(b);
  if (ab.byteLength !== bb.byteLength) return false;
  return crypto.subtle.timingSafeEqual(ab, bb);
}

/** Resolve a region-prefixed secret for the current shard. */
export function regionSecret(
  env: Env,
  name: "ADMIN_TOKEN" | "OPS_SYNC_TOKEN" | "ATTEST_CHALLENGE_KEY" | "FOOTBALL_DATA_TOKEN",
): string {
  if (env.SHARD_REGION === "uk") {
    switch (name) {
      case "ADMIN_TOKEN":         return env.UK_ADMIN_TOKEN ?? "";
      case "OPS_SYNC_TOKEN":      return env.UK_OPS_SYNC_TOKEN ?? "";
      case "ATTEST_CHALLENGE_KEY": return env.UK_ATTEST_CHALLENGE_KEY ?? "";
      case "FOOTBALL_DATA_TOKEN": return env.UK_FOOTBALL_DATA_TOKEN ?? "";
    }
  }
  switch (name) {
    case "ADMIN_TOKEN":         return env.EU_ADMIN_TOKEN ?? "";
    case "OPS_SYNC_TOKEN":      return env.EU_OPS_SYNC_TOKEN ?? "";
    case "ATTEST_CHALLENGE_KEY": return env.EU_ATTEST_CHALLENGE_KEY ?? "";
    case "FOOTBALL_DATA_TOKEN": return env.EU_FOOTBALL_DATA_TOKEN ?? "";
  }
}

/** True when the Authorization header carries the shard's admin bearer token. */
export function requireAdmin(env: Env, authorization: string | undefined): boolean {
  const token = regionSecret(env, "ADMIN_TOKEN");
  const provided = authorization?.startsWith("Bearer ") ? authorization.slice(7) : "";
  if (!token || !provided) return false;
  return timingSafeEqual(provided, token);
}

/** True when the Authorization header carries the shard's ops sync token. */
export function requireOps(env: Env, authorization: string | undefined): boolean {
  const token = regionSecret(env, "OPS_SYNC_TOKEN");
  const provided = authorization?.startsWith("Bearer ") ? authorization.slice(7) : "";
  if (!token || !provided) return false;
  return timingSafeEqual(provided, token);
}
