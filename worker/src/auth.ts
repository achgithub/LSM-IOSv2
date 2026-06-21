// Shared admin-token auth for guarded endpoints (/admin/*).

function timingSafeEqual(a: string, b: string): boolean {
  const enc = new TextEncoder();
  const ab = enc.encode(a);
  const bb = enc.encode(b);
  if (ab.byteLength !== bb.byteLength) return false;
  return crypto.subtle.timingSafeEqual(ab, bb);
}

/** True when the Authorization header carries the configured admin bearer token. */
export function requireAdmin(env: Env, authorization: string | undefined): boolean {
  const token = env.ADMIN_TOKEN;
  const provided = authorization?.startsWith("Bearer ") ? authorization.slice(7) : "";
  if (!token || !provided) return false;
  return timingSafeEqual(provided, token);
}

// OPS_SYNC_TOKEN is a single secret value shared verbatim across every league
// env plus the registry/orchestrator worker (see worker-registry). It exists
// so the orchestrator can call any league's /admin/sync-if-due without a
// per-league named secret — the secret surface stays flat as leagues scale.
export function requireOps(env: Env, authorization: string | undefined): boolean {
  const token = env.OPS_SYNC_TOKEN;
  const provided = authorization?.startsWith("Bearer ") ? authorization.slice(7) : "";
  if (!token || !provided) return false;
  return timingSafeEqual(provided, token);
}
