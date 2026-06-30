// Hono middleware: requires a valid JWT issued by any registered authority.
// Used on all manager-facing routes (backup, lifecycle, submissions).
// The /s/:token player PWA routes and /attest/* enrolment routes are excluded.

import type { Context, Next } from "hono";
import { parsePublicKeys, verifyJWT } from "../jwt";

export async function requireJWT(c: Context<{ Bindings: Env }>, next: Next) {
  const auth = c.req.header("Authorization");
  const token = auth?.startsWith("Bearer ") ? auth.slice(7) : null;
  if (!token) return c.json({ error: "authorization required" }, 401);

  const publicKeys = parsePublicKeys(c.env.JWT_PUBLIC_KEYS);
  const claims = await verifyJWT(token, publicKeys);
  if (!claims) return c.json({ error: "invalid or expired token" }, 401);

  return next();
}
