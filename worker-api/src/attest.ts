// Apple App Attest verification — the Phase 2 guard that lets ONLY the genuine
// iOS app reach the licensed football-data feed through this proxy.
//
// Two flows (see docs/app-attest-status.md):
//   1. Attestation (once per install): the app generates a Secure-Enclave key,
//      attests it against a server challenge, and POSTs the attestation object.
//      We verify the Apple cert chain + nonce + key id + app identity, then
//      persist the device public key with sign_count = 0.
//   2. Assertion (per session/refresh): the app signs a fresh server challenge
//      with the attested key. We verify the signature against the stored key and
//      require the sign counter to advance (replay protection).
//
// Challenges are STATELESS: an HMAC over (nonce.timestamp) with ATTEST_CHALLENGE_KEY,
// validated within a short window — no KV writes (free-plan friendly). Replay is
// stopped by the monotonic counter, not by single-use challenges.
//
// Crypto: WebCrypto (crypto.subtle) for SHA-256 / ECDSA-P256 / HMAC; @peculiar/x509
// for the X.509 chain; @levischuck/tiny-cbor (pure JS — Workers safe) for CBOR.

import { type CBORType, decodeCBOR } from "@levischuck/tiny-cbor";
import { X509Certificate, cryptoProvider } from "@peculiar/x509";

// @peculiar/x509 needs a WebCrypto provider; the Workers runtime global is one.
cryptoProvider.set(crypto as Crypto);

// Apple App Attest Root CA (https://www.apple.com/certificateauthority/).
// SHA256 fingerprint 1C:B9:82:3B:A2:8B:A6:AD:2D:33:A0:06:94:1D:E2:AE:4F:51:3E:F1:D4:E8:31:B9:F7:E0:FA:7B:62:42:C9:32
const APPLE_APP_ATTEST_ROOT_CA = `-----BEGIN CERTIFICATE-----
MIICITCCAaegAwIBAgIQC/O+DvHN0uD7jG5yH2IXmDAKBggqhkjOPQQDAzBSMSYw
JAYDVQQDDB1BcHBsZSBBcHAgQXR0ZXN0YXRpb24gUm9vdCBDQTETMBEGA1UECgwK
QXBwbGUgSW5jLjETMBEGA1UECAwKQ2FsaWZvcm5pYTAeFw0yMDAzMTgxODMyNTNa
Fw00NTAzMTUwMDAwMDBaMFIxJjAkBgNVBAMMHUFwcGxlIEFwcCBBdHRlc3RhdGlv
biBSb290IENBMRMwEQYDVQQKDApBcHBsZSBJbmMuMRMwEQYDVQQIDApDYWxpZm9y
bmlhMHYwEAYHKoZIzj0CAQYFK4EEACIDYgAERTHhmLW07ATaFQIEVwTtT4dyctdh
NbJhFs/Ii2FdCgAHGbpphY3+d8qjuDngIN3WVhQUBHAoMeQ/cLiP1sOUtgjqK9au
Yen1mMEvRq9Sk3Jm5X8U62H+xTD3FE9TgS41o0IwQDAPBgNVHRMBAf8EBTADAQH/
MB0GA1UdDgQWBBSskRBTM72+aEH/pwyp5frq5eWKoTAOBgNVHQ8BAf8EBAMCAQYw
CgYIKoZIzj0EAwMDaAAwZQIwQgFGnByvsiVbpTKwSga0kP0e8EeDS4+sQmTvb7vn
53O5+FRXgeLhpJ06ysC5PrOyAjEAp5U4xDgEgllF7En3VcE3iexZZtKeYnpqtijV
oyFraWVIyd/dganmrduC1bmTBGwD
-----END CERTIFICATE-----`;

// credCert extension carrying the attestation nonce (Apple OID).
const NONCE_OID = "1.2.840.113635.100.8.2";

// AAGUID values in authData identifying the App Attest environment.
const AAGUID_PROD = "appattest\0\0\0\0\0\0\0";
const AAGUID_DEV = "appattestdevelop";

export type AttestEnvironment = "production" | "development";

export interface AttestConfig {
  teamId: string;
  bundleId: string;
  /** Which AAGUID to require. Sandbox/dev builds attest in "development". */
  environment: AttestEnvironment;
}

export interface VerifiedAttestation {
  /** base64 of the raw uncompressed P-256 public point (65 bytes). */
  publicKey: string;
  /** sign counter from authData (0 for a fresh attestation). */
  signCount: number;
  environment: AttestEnvironment;
}

// ── small encoders ────────────────────────────────────────────────────────────

function b64ToBytes(b64: string): Uint8Array {
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

function bytesToB64(bytes: Uint8Array): string {
  let bin = "";
  for (const byte of bytes) bin += String.fromCharCode(byte);
  return btoa(bin);
}

function bytesEqual(a: Uint8Array, b: Uint8Array): boolean {
  if (a.byteLength !== b.byteLength) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= (a[i] as number) ^ (b[i] as number);
  return diff === 0;
}

function concatBytes(a: Uint8Array, b: Uint8Array): Uint8Array {
  const out = new Uint8Array(a.length + b.length);
  out.set(a, 0);
  out.set(b, a.length);
  return out;
}

async function sha256(data: Uint8Array): Promise<Uint8Array> {
  return new Uint8Array(await crypto.subtle.digest("SHA-256", data));
}

// ── Stateless HMAC challenges ───────────────────────────────────────────────

async function hmacKey(secret: string): Promise<CryptoKey> {
  return crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign", "verify"],
  );
}

/**
 * Issue an opaque challenge string `v1.<nonceHex>.<ts>.<macB64>`. The client
 * hashes the UTF-8 bytes of this exact string as its clientData. Stateless: no
 * storage — the HMAC + timestamp are self-validating.
 */
export async function issueChallenge(secret: string): Promise<string> {
  const nonce = crypto.getRandomValues(new Uint8Array(16));
  const nonceHex = Array.from(nonce, (b) => b.toString(16).padStart(2, "0")).join("");
  const payload = `v1.${nonceHex}.${Date.now()}`;
  const key = await hmacKey(secret);
  const mac = new Uint8Array(
    await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(payload)),
  );
  return `${payload}.${bytesToB64(mac)}`;
}

/** Verify a challenge: HMAC valid and issued within `maxAgeMs`. */
export async function verifyChallenge(
  secret: string,
  challenge: string,
  maxAgeMs: number,
): Promise<boolean> {
  const lastDot = challenge.lastIndexOf(".");
  if (lastDot < 0) return false;
  const payload = challenge.slice(0, lastDot);
  const macB64 = challenge.slice(lastDot + 1);
  const parts = payload.split(".");
  if (parts.length !== 3 || parts[0] !== "v1") return false;
  const ts = Number(parts[2]);
  if (!Number.isFinite(ts) || Date.now() - ts > maxAgeMs || ts - Date.now() > 60_000) {
    return false;
  }
  let mac: Uint8Array;
  try {
    mac = b64ToBytes(macB64);
  } catch {
    return false;
  }
  const key = await hmacKey(secret);
  return crypto.subtle.verify("HMAC", key, mac, new TextEncoder().encode(payload));
}

// ── authenticatorData parsing ───────────────────────────────────────────────

interface AuthData {
  rpIdHash: Uint8Array; // 32
  signCount: number;
  aaguid: Uint8Array | null; // 16, attestation only
  credentialId: Uint8Array | null; // attestation only
}

function parseAuthData(authData: Uint8Array, withCredential: boolean): AuthData {
  if (authData.length < 37) throw new Error("authData too short");
  const rpIdHash = authData.slice(0, 32);
  const view = new DataView(authData.buffer, authData.byteOffset, authData.byteLength);
  const signCount = view.getUint32(33, false);
  if (!withCredential) {
    return { rpIdHash, signCount, aaguid: null, credentialId: null };
  }
  if (authData.length < 55) throw new Error("authData missing attested credential data");
  const aaguid = authData.slice(37, 53);
  const credIdLen = view.getUint16(53, false);
  const credentialId = authData.slice(55, 55 + credIdLen);
  return { rpIdHash, signCount, aaguid, credentialId };
}

function aaguidString(aaguid: Uint8Array): string {
  return new TextDecoder("latin1").decode(aaguid);
}

// ── X.509 chain ─────────────────────────────────────────────────────────────

async function verifyChain(x5c: Uint8Array[]): Promise<X509Certificate> {
  const [leafDer, interDer] = x5c;
  if (!leafDer || !interDer) throw new Error("attestation x5c chain too short");
  const leaf = new X509Certificate(leafDer);
  const intermediate = new X509Certificate(interDer);
  const root = new X509Certificate(APPLE_APP_ATTEST_ROOT_CA);

  const now = new Date();
  for (const cert of [leaf, intermediate]) {
    if (now < cert.notBefore || now > cert.notAfter) {
      throw new Error("attestation certificate expired or not yet valid");
    }
  }

  const rootKey = await root.publicKey.export();
  const interKey = await intermediate.publicKey.export();
  const interSignedByRoot = await intermediate.verify({ publicKey: rootKey, signatureOnly: true });
  const leafSignedByInter = await leaf.verify({ publicKey: interKey, signatureOnly: true });
  if (!interSignedByRoot || !leafSignedByInter) {
    throw new Error("attestation certificate chain does not verify to Apple root");
  }
  return leaf;
}

/** Pull the nonce out of the credCert's Apple OID extension (OCTET STRING inside). */
function nonceFromCert(leaf: X509Certificate): Uint8Array {
  const ext = leaf.getExtension(NONCE_OID);
  if (!ext) throw new Error("credCert missing nonce extension");
  // The extension value is DER: SEQUENCE { [1] EXPLICIT OCTET STRING(nonce) }.
  // The 32-byte nonce is the trailing octets; locate the final 32 bytes of the
  // innermost OCTET STRING rather than hand-rolling a full ASN.1 walk.
  const raw = new Uint8Array(ext.value);
  if (raw.length < 32) throw new Error("nonce extension malformed");
  return raw.slice(raw.length - 32);
}

// ── Public key helpers ──────────────────────────────────────────────────────

/** Export the leaf cert's EC public key as the raw 65-byte uncompressed point. */
async function leafRawPublicKey(leaf: X509Certificate): Promise<Uint8Array> {
  const key = await crypto.subtle.importKey(
    "spki",
    leaf.publicKey.rawData,
    { name: "ECDSA", namedCurve: "P-256" },
    true,
    ["verify"],
  );
  return new Uint8Array((await crypto.subtle.exportKey("raw", key)) as ArrayBuffer);
}

async function importVerifyKey(rawPoint: Uint8Array): Promise<CryptoKey> {
  return crypto.subtle.importKey(
    "raw",
    rawPoint,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["verify"],
  );
}

/** ECDSA DER signature (SEQUENCE{INTEGER r, INTEGER s}) → IEEE-P1363 r||s (64 bytes). */
function derToRawSignature(der: Uint8Array): Uint8Array {
  let offset = 0;
  if (der[offset++] !== 0x30) throw new Error("bad signature: no SEQUENCE");
  // sequence length (assume short form — ECDSA-P256 sigs are < 128 bytes)
  offset++;
  const readInt = (): Uint8Array => {
    if (der[offset++] !== 0x02) throw new Error("bad signature: no INTEGER");
    const len = der[offset++];
    if (len === undefined) throw new Error("bad signature: truncated INTEGER");
    let val = der.slice(offset, offset + len);
    offset += len;
    // strip leading zero padding, then left-pad to 32 bytes
    while (val.length > 1 && val[0] === 0x00) val = val.slice(1);
    if (val.length > 32) throw new Error("bad signature: integer too long");
    const padded = new Uint8Array(32);
    padded.set(val, 32 - val.length);
    return padded;
  };
  const r = readInt();
  const s = readInt();
  return concatBytes(r, s);
}

// ── CBOR map helpers (tiny-cbor decodes CBOR maps to JS Map) ─────────────────

function asMap(v: CBORType): Map<string | number, CBORType> {
  if (!(v instanceof Map)) throw new Error("expected CBOR map");
  return v;
}

function getBytes(m: Map<string | number, CBORType>, key: string): Uint8Array {
  const v = m.get(key);
  if (!(v instanceof Uint8Array)) throw new Error(`CBOR field ${key} is not bytes`);
  return v;
}

// ── Attestation verification ────────────────────────────────────────────────

/**
 * Verify an attestation object (base64) for `keyId` (base64) against `challenge`.
 * Returns the device public key + initial counter to persist, or throws.
 */
export async function verifyAttestation(
  attestationB64: string,
  keyIdB64: string,
  challenge: string,
  cfg: AttestConfig,
): Promise<VerifiedAttestation> {
  const decoded = asMap(decodeCBOR(b64ToBytes(attestationB64)));
  if (decoded.get("fmt") !== "apple-appattest") throw new Error("unexpected attestation fmt");
  const attStmt = asMap(decoded.get("attStmt") as CBORType);
  const x5cRaw = attStmt.get("x5c");
  if (!Array.isArray(x5cRaw) || !x5cRaw.every((c) => c instanceof Uint8Array)) {
    throw new Error("attestation x5c missing or malformed");
  }
  const x5c = x5cRaw as Uint8Array[];
  const authData = getBytes(decoded, "authData");

  // 1. Chain to Apple root.
  const leaf = await verifyChain(x5c);

  // 2. nonce = SHA256(authData || SHA256(challenge)) must match the cert extension.
  const clientDataHash = await sha256(new TextEncoder().encode(challenge));
  const expectedNonce = await sha256(concatBytes(authData, clientDataHash));
  if (!bytesEqual(expectedNonce, nonceFromCert(leaf))) {
    throw new Error("attestation nonce mismatch (challenge replay or tampering)");
  }

  // 3. keyId == SHA256(public key); also matches the credentialId in authData.
  const rawPublicKey = await leafRawPublicKey(leaf);
  const computedKeyId = await sha256(rawPublicKey);
  const claimedKeyId = b64ToBytes(keyIdB64);
  if (!bytesEqual(computedKeyId, claimedKeyId)) throw new Error("keyId does not match public key");

  // 4. app identity: rpIdHash == SHA256("TeamID.BundleID"); AAGUID == environment.
  const parsed = parseAuthData(authData, true);
  const expectedRpId = await sha256(new TextEncoder().encode(`${cfg.teamId}.${cfg.bundleId}`));
  if (!bytesEqual(expectedRpId, parsed.rpIdHash)) throw new Error("rpId hash mismatch (wrong app)");
  if (parsed.credentialId && !bytesEqual(parsed.credentialId, claimedKeyId)) {
    throw new Error("credentialId does not match keyId");
  }
  const aaguid = parsed.aaguid ? aaguidString(parsed.aaguid) : "";
  const expectedAaguid = cfg.environment === "production" ? AAGUID_PROD : AAGUID_DEV;
  if (aaguid !== expectedAaguid) throw new Error(`unexpected App Attest environment: ${aaguid}`);

  return {
    publicKey: bytesToB64(rawPublicKey),
    signCount: parsed.signCount,
    environment: cfg.environment,
  };
}

// ── Assertion verification ──────────────────────────────────────────────────

export interface VerifiedAssertion {
  /** new sign counter — caller persists it (must be > stored value). */
  signCount: number;
}

/**
 * Verify an assertion (base64) signed by the stored public key over `challenge`.
 * Enforces the rpId and a strictly-increasing counter vs `previousSignCount`.
 */
export async function verifyAssertion(
  assertionB64: string,
  storedPublicKeyB64: string,
  previousSignCount: number,
  challenge: string,
  cfg: AttestConfig,
): Promise<VerifiedAssertion> {
  const decoded = asMap(decodeCBOR(b64ToBytes(assertionB64)));
  const signature = getBytes(decoded, "signature");
  const authenticatorData = getBytes(decoded, "authenticatorData");

  const clientDataHash = await sha256(new TextEncoder().encode(challenge));
  // Apple's Secure Enclave uses ECDSA-SHA256 to sign SHA256(authData || clientDataHash).
  // ECDSA-SHA256 applies its own SHA256 to whatever you pass it, so the SE effectively
  // signs SHA256(SHA256(authData || clientDataHash)).
  // WebCrypto verify({ hash: "SHA-256" }) also applies SHA256 to its `data` argument,
  // so we pass the pre-computed SHA256(authData || clientDataHash) and let WebCrypto
  // apply the final hash — matching what the SE signed. Confirmed empirically.
  const innerHash = await sha256(concatBytes(authenticatorData, clientDataHash));
  const key = await importVerifyKey(b64ToBytes(storedPublicKeyB64));
  const ok = await crypto.subtle.verify(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    derToRawSignature(signature),
    innerHash,
  );
  if (!ok) throw new Error("assertion signature invalid");

  const parsed = parseAuthData(authenticatorData, false);
  const expectedRpId = await sha256(new TextEncoder().encode(`${cfg.teamId}.${cfg.bundleId}`));
  if (!bytesEqual(expectedRpId, parsed.rpIdHash)) throw new Error("assertion rpId mismatch");
  if (parsed.signCount <= previousSignCount) {
    throw new Error("assertion counter did not advance (replay)");
  }
  return { signCount: parsed.signCount };
}
