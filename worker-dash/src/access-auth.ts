// Validates the Cloudflare Access JWT this Worker currently just trusts
// implicitly. Access attaches a signed `Cf-Access-Jwt-Assertion` header to
// every request that's passed its edge policy — verifying it here (signature,
// audience, expiry) means this Worker fails closed if that Access policy is
// ever disabled/misconfigured, rather than silently serving whatever reaches
// it. RS256 + a remote JWKS here, since that's what Cloudflare Access issues
// (vs. worker-api/src/jwt.ts's ES256 + baked-in keys for our own authority
// tokens — different issuer, different key-distribution model).

interface JWK {
  kid: string;
  n: string;
  e: string;
  kty: string;
}

let cachedKeys: { keys: JWK[]; fetchedAt: number } | null = null;
const JWKS_TTL_MS = 60 * 60 * 1000; // re-fetch at most hourly

function b64urlToBytes(s: string): Uint8Array {
  const b64 = s.replace(/-/g, "+").replace(/_/g, "/");
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i) ?? 0;
  return out;
}

function decodeB64url(s: string): unknown {
  const b64 = s.replace(/-/g, "+").replace(/_/g, "/");
  return JSON.parse(atob(b64));
}

async function fetchJWKS(teamDomain: string): Promise<JWK[]> {
  if (cachedKeys && Date.now() - cachedKeys.fetchedAt < JWKS_TTL_MS) return cachedKeys.keys;
  const res = await fetch(`https://${teamDomain}/cdn-cgi/access/certs`);
  if (!res.ok) throw new Error(`JWKS fetch failed: ${res.status}`);
  const body = await res.json<{ keys: JWK[] }>();
  cachedKeys = { keys: body.keys, fetchedAt: Date.now() };
  return body.keys;
}

/**
 * Verifies the `Cf-Access-Jwt-Assertion` header. Checks signature (against
 * the team's published JWKS), audience (this specific Access Application),
 * and expiry/not-before. Any failure — missing header, bad signature, wrong
 * audience, expired, or the JWKS endpoint being unreachable — returns false;
 * callers should reject the request on any `false`, not just log it.
 */
export async function verifyAccessJWT(
  token: string | null,
  teamDomain: string | undefined,
  audience: string | undefined,
): Promise<boolean> {
  if (!token || !teamDomain || !audience) return false;

  const parts = token.split(".");
  if (parts.length !== 3) return false;
  const [headerB64, payloadB64, sigB64] = parts as [string, string, string];

  let header: { alg?: string; kid?: string };
  let payload: { aud?: string[] | string; exp?: number; nbf?: number };
  try {
    header = decodeB64url(headerB64) as typeof header;
    payload = decodeB64url(payloadB64) as typeof payload;
  } catch {
    return false;
  }
  if (header.alg !== "RS256" || !header.kid) return false;

  const now = Math.floor(Date.now() / 1000);
  if (!payload.exp || payload.exp < now) return false;
  if (payload.nbf && payload.nbf > now) return false;

  const aud = Array.isArray(payload.aud) ? payload.aud : payload.aud ? [payload.aud] : [];
  if (!aud.includes(audience)) return false;

  let jwk: JWK | undefined;
  try {
    const keys = await fetchJWKS(teamDomain);
    jwk = keys.find((k) => k.kid === header.kid);
  } catch {
    return false; // JWKS unreachable — fail closed, not open
  }
  if (!jwk) return false;

  try {
    const key = await crypto.subtle.importKey(
      "jwk",
      { kty: jwk.kty, n: jwk.n, e: jwk.e, alg: "RS256", ext: true },
      { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
      false,
      ["verify"],
    );
    const data = new TextEncoder().encode(`${headerB64}.${payloadB64}`);
    const sig = b64urlToBytes(sigB64);
    return await crypto.subtle.verify("RSASSA-PKCS1-v1_5", key, sig, data);
  } catch {
    return false;
  }
}
