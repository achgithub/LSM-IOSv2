// JWT signing and verification for the LSM authority Worker.
//
// Algorithm: ES256 (ECDSA P-256, SHA-256) — same elliptic curve as App Attest,
// so no extra crypto dependency is needed beyond what the Workers runtime provides.
//
// Key lifecycle:
//   • Each region has one active private key stored as a Worker secret
//     (<REGION>_JWT_PRIVATE_KEY, base64 PKCS8 DER).
//   • The corresponding public key lives in JWT_PUBLIC_KEYS (a JSON map of
//     kid → base64 SPKI DER) — a wrangler.jsonc var replicated to every
//     sports shard and to the authority itself for verifying incoming tokens.
//   • On rotation: generate a new keypair, set the new private key secret,
//     add the new public key to JWT_PUBLIC_KEYS, bump JWT_KID, redeploy.
//     Old tokens with the previous kid verify fine until their 15-min TTL expires
//     — no forced logout, no dual-key complexity needed in the issuer.
//   • To generate a keypair (Web Crypto API, run once in a browser console):
//
//       const kp = await crypto.subtle.generateKey(
//         { name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]
//       );
//       const priv = btoa(String.fromCharCode(
//         ...new Uint8Array(await crypto.subtle.exportKey("pkcs8", kp.privateKey))
//       ));
//       const pub = btoa(String.fromCharCode(
//         ...new Uint8Array(await crypto.subtle.exportKey("spki", kp.publicKey))
//       ));
//       console.log("PRIVATE (secret):", priv);
//       console.log("PUBLIC  (var):", pub);

const ALG = { name: "ECDSA", namedCurve: "P-256" } as const;
const HASH = "SHA-256";
export const JWT_TTL_SECONDS = 900; // 15 min

// ── Base64 helpers ────────────────────────────────────────────────────────────

function b64ToBytes(b64: string): Uint8Array {
  // Accept both standard base64 (+/) and base64url (-_), with or without padding.
  const normalised = b64.replace(/-/g, "+").replace(/_/g, "/");
  const bin = atob(normalised);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i) ?? 0;
  return out;
}

function bytesToB64url(bytes: Uint8Array): string {
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=/g, "");
}

function encodeB64url(obj: unknown): string {
  return bytesToB64url(new TextEncoder().encode(JSON.stringify(obj)));
}

function decodeB64url(s: string): unknown {
  const b64 = s.replace(/-/g, "+").replace(/_/g, "/");
  return JSON.parse(atob(b64));
}

// ── Key import ────────────────────────────────────────────────────────────────

function importPrivateKey(b64pkcs8: string): Promise<CryptoKey> {
  return crypto.subtle.importKey("pkcs8", b64ToBytes(b64pkcs8), ALG, false, ["sign"]);
}

function importPublicKey(b64spki: string): Promise<CryptoKey> {
  return crypto.subtle.importKey("spki", b64ToBytes(b64spki), ALG, false, ["verify"]);
}

// ── Signing ───────────────────────────────────────────────────────────────────

export async function signJWT(privateKeyB64: string, kid: string, issuer: string): Promise<string> {
  const key = await importPrivateKey(privateKeyB64);
  const now = Math.floor(Date.now() / 1000);
  const header = encodeB64url({ alg: "ES256", typ: "JWT", kid });
  const payload = encodeB64url({ iss: issuer, iat: now, exp: now + JWT_TTL_SECONDS });
  const toSign = new TextEncoder().encode(`${header}.${payload}`);
  const sig = await crypto.subtle.sign({ name: "ECDSA", hash: HASH }, key, toSign);
  return `${header}.${payload}.${bytesToB64url(new Uint8Array(sig))}`;
}

// ── Verification ──────────────────────────────────────────────────────────────

export interface JWTClaims {
  kid: string;
  iss: string;
  iat: number;
  exp: number;
}

/** Verify a JWT against the known-public-keys map. Returns claims or null. */
export async function verifyJWT(
  token: string,
  publicKeys: Record<string, string>,
): Promise<JWTClaims | null> {
  const parts = token.split(".");
  if (parts.length !== 3) return null;
  const [headerB64, payloadB64, sigB64] = parts as [string, string, string];

  let header: { alg?: string; kid?: string };
  let payload: { iss?: string; iat?: number; exp?: number };
  try {
    header = decodeB64url(headerB64) as typeof header;
    payload = decodeB64url(payloadB64) as typeof payload;
  } catch {
    return null;
  }

  if (header.alg !== "ES256" || !header.kid) return null;

  const pubKeyB64 = publicKeys[header.kid];
  if (!pubKeyB64) return null; // unknown key id — reject, don't fall through

  const now = Math.floor(Date.now() / 1000);
  if (!payload.exp || payload.exp < now) return null;         // expired
  if (!payload.iat || payload.iat > now + 60) return null;    // future-dated (clock skew grace)
  if (!payload.iss) return null;

  try {
    const key = await importPublicKey(pubKeyB64);
    const data = new TextEncoder().encode(`${headerB64}.${payloadB64}`);
    const sig = b64ToBytes(sigB64);
    const valid = await crypto.subtle.verify({ name: "ECDSA", hash: HASH }, key, sig, data);
    if (!valid) return null;
  } catch {
    return null;
  }

  return {
    kid: header.kid,
    iss: payload.iss,
    iat: payload.iat!,
    exp: payload.exp!,
  };
}

/** Parse JWT_PUBLIC_KEYS env var (JSON string) into a kid→key map. */
export function parsePublicKeys(raw: string): Record<string, string> {
  try {
    const parsed: unknown = JSON.parse(raw);
    if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
      return parsed as Record<string, string>;
    }
  } catch { /* fall through */ }
  return {};
}
