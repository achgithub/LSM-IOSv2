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
