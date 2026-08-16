// OTP issuance/verification against the FLAGS KV namespace, plus the
// pending-bind ticket used to authorize a device-transfer register call.
// Follows the "otp:"-namespaced key convention (same colon-namespacing idea
// as src/outage.ts's "outage:" key), one flat shared KV, native TTL for
// expiry. Codes are 6-digit numeric and hashed before storage — the raw
// code only ever exists in the response handed to email.ts, never at rest.

const OTP_TTL_SECONDS = 600; // 10 min
const RESEND_COOLDOWN_SECONDS = 60;
const MAX_ATTEMPTS = 5;
const PENDING_BIND_TTL_SECONDS = 300; // 5 min — window between OTP verify and register completing

export function registerOtpKey(managerToken: string): string {
  return `otp:register:${managerToken}`;
}

export function linkDeviceOtpKey(email: string): string {
  return `otp:link:${email}`;
}

interface OtpEntry<T> {
  codeHash: string;
  attempts: number;
  issuedAt: string; // ISO8601
  payload: T;
}

async function hashCode(code: string): Promise<string> {
  const data = new TextEncoder().encode(code);
  const digest = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

function generateCode(): string {
  const bytes = new Uint8Array(4);
  crypto.getRandomValues(bytes);
  const n = new DataView(bytes.buffer).getUint32(0) % 1_000_000;
  return n.toString().padStart(6, "0");
}

export type OtpIssueResult = { code: string } | { error: "cooldown"; retryAfterSeconds: number };

// Overwrites any existing entry for this key unless it was issued within
// the resend cooldown window.
export async function issueOtp<T>(kv: KVNamespace, key: string, payload: T): Promise<OtpIssueResult> {
  const existingRaw = await kv.get(key);
  if (existingRaw) {
    try {
      const existing = JSON.parse(existingRaw) as OtpEntry<T>;
      const elapsedSeconds = (Date.now() - new Date(existing.issuedAt).getTime()) / 1000;
      if (elapsedSeconds < RESEND_COOLDOWN_SECONDS) {
        return { error: "cooldown", retryAfterSeconds: Math.ceil(RESEND_COOLDOWN_SECONDS - elapsedSeconds) };
      }
    } catch {
      // malformed existing entry — fall through and overwrite
    }
  }

  const code = generateCode();
  const entry: OtpEntry<T> = {
    codeHash: await hashCode(code),
    attempts: 0,
    issuedAt: new Date().toISOString(),
    payload,
  };
  await kv.put(key, JSON.stringify(entry), { expirationTtl: OTP_TTL_SECONDS });
  return { code };
}

export type OtpVerifyResult<T> =
  | { ok: true; payload: T }
  | { ok: false; error: "not_found" | "too_many_attempts" | "incorrect" };

export async function verifyOtp<T>(kv: KVNamespace, key: string, code: string): Promise<OtpVerifyResult<T>> {
  const raw = await kv.get(key);
  if (!raw) return { ok: false, error: "not_found" };

  let entry: OtpEntry<T>;
  try {
    entry = JSON.parse(raw) as OtpEntry<T>;
  } catch {
    await kv.delete(key);
    return { ok: false, error: "not_found" };
  }

  if (entry.attempts >= MAX_ATTEMPTS) {
    await kv.delete(key);
    return { ok: false, error: "too_many_attempts" };
  }

  const codeHash = await hashCode(code);
  if (codeHash !== entry.codeHash) {
    entry.attempts += 1;
    if (entry.attempts >= MAX_ATTEMPTS) {
      await kv.delete(key);
    } else {
      await kv.put(key, JSON.stringify(entry), { expirationTtl: OTP_TTL_SECONDS });
    }
    return { ok: false, error: "incorrect" };
  }

  await kv.delete(key);
  return { ok: true, payload: entry.payload };
}

// ── Pending-bind ticket ──────────────────────────────────────────────────────
// Written by POST /account/link-device/verify once OTP proves email
// ownership; consumed by the register-guard inside POST /attest/register to
// authorize swapping active_key_id to a new device. A ticket authorizes
// exactly one register attempt, not a window of retries — consumePendingBind
// reads and deletes in the same call.

function pendingBindKey(managerToken: string): string {
  return `pending_bind:${managerToken}`;
}

export async function writePendingBind(kv: KVNamespace, managerToken: string): Promise<void> {
  await kv.put(pendingBindKey(managerToken), "1", { expirationTtl: PENDING_BIND_TTL_SECONDS });
}

export async function consumePendingBind(kv: KVNamespace, managerToken: string): Promise<boolean> {
  const key = pendingBindKey(managerToken);
  const existing = await kv.get(key);
  if (!existing) return false;
  await kv.delete(key);
  return true;
}
