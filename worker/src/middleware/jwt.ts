// Hono middleware: verifies a Bearer JWT issued by a regional authority Worker.
// Used on sports-data routes that require the genuine iOS app (/scores, /fixtures).
//
// Public keys for all known authorities are stored in the JWT_PUBLIC_KEYS wrangler
// var (JSON: { "<kid>": "<base64 SPKI>" }). Adding a new region = add its public
// key here and redeploy — no code change required.

import type { Context, Next } from "hono";

const ALG = { name: "ECDSA", namedCurve: "P-256" } as const;
const HASH = "SHA-256";

function b64ToBytes(b64: string): Uint8Array {
  const normalised = b64.replace(/-/g, "+").replace(/_/g, "/");
  const bin = atob(normalised);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i) ?? 0;
  return out;
}

function decodeB64url(s: string): unknown {
  return JSON.parse(atob(s.replace(/-/g, "+").replace(/_/g, "/")));
}

function parsePublicKeys(raw: string): Record<string, string> {
  try {
    const p: unknown = JSON.parse(raw);
    if (p && typeof p === "object" && !Array.isArray(p)) return p as Record<string, string>;
  } catch { /* fall through */ }
  return {};
}

export async function requireJWT(c: Context<{ Bindings: Env }>, next: Next) {
  if (c.env.ATTEST_DEV_BYPASS === "1") return next();

  const auth = c.req.header("Authorization");
  const token = auth?.startsWith("Bearer ") ? auth.slice(7) : null;
  if (!token) return c.json({ error: "authorization required" }, 401);

  const parts = token.split(".");
  if (parts.length !== 3) return c.json({ error: "invalid token" }, 401);
  const [headerB64, payloadB64, sigB64] = parts as [string, string, string];

  let header: { alg?: string; kid?: string };
  let payload: { exp?: number; iat?: number };
  try {
    header = decodeB64url(headerB64) as typeof header;
    payload = decodeB64url(payloadB64) as typeof payload;
  } catch {
    return c.json({ error: "invalid token" }, 401);
  }

  if (header.alg !== "ES256" || !header.kid) return c.json({ error: "invalid token" }, 401);

  const publicKeys = parsePublicKeys(c.env.JWT_PUBLIC_KEYS ?? "{}");
  const pubKeyB64 = publicKeys[header.kid];
  if (!pubKeyB64) return c.json({ error: "unknown key id" }, 401);

  const now = Math.floor(Date.now() / 1000);
  if (!payload.exp || payload.exp < now) return c.json({ error: "token expired" }, 401);
  if (!payload.iat || payload.iat > now + 60) return c.json({ error: "invalid token" }, 401);

  try {
    const key = await crypto.subtle.importKey(
      "spki", b64ToBytes(pubKeyB64), ALG, false, ["verify"],
    );
    const data = new TextEncoder().encode(`${headerB64}.${payloadB64}`);
    const valid = await crypto.subtle.verify(
      { name: "ECDSA", hash: HASH }, key, b64ToBytes(sigB64), data,
    );
    if (!valid) return c.json({ error: "invalid token" }, 401);
  } catch {
    return c.json({ error: "invalid token" }, 401);
  }

  return next();
}

