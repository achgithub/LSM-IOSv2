import { Hono } from "hono";
import {
  getAccountByEmail,
  getManagerTokensByEmail,
  upsertAccount,
  linkAccount,
} from "../account-store";
import { issueOtp, verifyOtp, registerOtpKey, linkDeviceOtpKey, writePendingBind } from "../otp";
import { sendOtpEmail, EmailSendError } from "../email";
import { resolveManagerDB } from "../shardRouter";

// ── Email registration for device recovery ───────────────────────────────────
//
// Not a login/session system — see schema.sql's comment on the accounts
// table. Two flows, kept deliberately separate:
//
//   POST /account/register + /account/verify   — an already-attested device
//   (behind requireJWT, see index.ts) links an email to its manager_token.
//   Nothing about any game is touched.
//
//   POST /account/link-device/request + /verify — public, no JWT (a
//   new/lost-phone device has no attested identity yet). Proving email
//   ownership returns the linked manager_token and opens a short
//   pending-bind window that the device's *next* /attest/register call must
//   consume to become the active device — see the guard in routes/attest.ts.
//
// The `accounts` table itself is not shard-routed — queried via c.env.DB
// directly, same as the admin device-management routes. See schema.sql's
// comment on accounts for why. The one exception is the cloud-entitlement
// check on register/verify below, which reads `manager_lifecycle` and so
// does have to resolve the manager's shard.

export const account = new Hono<{ Bindings: Env }>();

function managerTokenHeader(c: { req: { header: (name: string) => string | undefined } }): string | null {
  return c.req.header("X-Manager-Token")?.toLowerCase() ?? null;
}

function normalizeEmail(email: string): string {
  return email.trim().toLowerCase();
}

function shardHeader(c: { req: { header: (name: string) => string | undefined } }): string | null {
  return c.req.header("X-Shard-Id") ?? null;
}

// Registering an email is a cloud feature — leagues_3 and above (see
// Entitlements.canUseCloud in the iOS app). The app hides the registration
// form below that tier, but a client-side rule is a UI convention, not a
// gate, so it's enforced here too.
//
// `max_pwa_links` is the server's only view of tier: reported by the client
// on every launch (POST /manager/entitlements) and non-null exactly for the
// cloud tiers. That makes it a soft signal rather than proof — tier is a
// StoreKit concept the server can't verify, so a hand-crafted request could
// claim anything. This closes the casual path, not a determined one.
//
// Fails OPEN in both uncertain cases — no row, or a lookup error. A manager
// the server has never heard of is mid-first-launch, not a free-rider, and
// rejecting them would break registration for a paying customer whose
// entitlement report hasn't landed yet (it's fire-and-forget). Only a row
// that positively says "no cloud tier" is refused.
//
// Deliberately NOT applied to the link-device routes below: those are
// recovery, they run on a device with no attested identity or resolved tier
// by definition, and they gate themselves — you can only link to an account
// that already exists, and accounts are only created by an entitled manager.
async function hasCloudEntitlement(
  c: { env: Env; req: { header: (name: string) => string | undefined } },
  managerToken: string
): Promise<boolean> {
  try {
    const { db } = await resolveManagerDB(c.env, shardHeader(c), managerToken);
    const row = await db
      .prepare(`SELECT max_pwa_links FROM manager_lifecycle WHERE manager_token = ?`)
      .bind(managerToken)
      .first<{ max_pwa_links: number | null }>();
    if (!row) return true;
    return row.max_pwa_links != null;
  } catch (err) {
    console.error(JSON.stringify({
      msg: "cloud entitlement lookup failed, allowing", route: "account", error: String(err),
    }));
    return true;
  }
}

// ─── Register (already-live device) ─────────────────────────────────────────

// POST /account/register
// Body: { email }. Issues an OTP tied to this device's manager_token.
account.post("/register", async (c) => {
  const managerToken = managerTokenHeader(c);
  if (!managerToken) return c.json({ error: "X-Manager-Token header is required" }, 400);

  let body: { email?: string };
  try { body = await c.req.json(); } catch {
    return c.json({ error: "invalid json" }, 400);
  }
  const email = body.email ? normalizeEmail(body.email) : null;
  if (!email) return c.json({ error: "email is required" }, 400);

  if (!(await hasCloudEntitlement(c, managerToken))) {
    return c.json({ error: "cloud_tier_required" }, 403);
  }

  const result = await issueOtp(c.env.FLAGS, registerOtpKey(managerToken), { email });
  if ("error" in result) {
    return c.json({ error: "too many requests, try again shortly", retryAfterSeconds: result.retryAfterSeconds }, 429);
  }

  try {
    await sendOtpEmail(c.env, email, result.code);
  } catch (err) {
    console.error(JSON.stringify({ msg: "otp send failed", route: "register", error: String(err instanceof EmailSendError ? err.message : err) }));
    return c.json({ error: "failed to send code" }, 502);
  }

  return c.json({ ok: true });
});

// POST /account/verify
// Body: { email, otp, keyId } — keyId is this device's own App Attest key,
// client-supplied (same as it already sends to /attest/register).
account.post("/verify", async (c) => {
  const managerToken = managerTokenHeader(c);
  if (!managerToken) return c.json({ error: "X-Manager-Token header is required" }, 400);

  let body: { email?: string; otp?: string; keyId?: string };
  try { body = await c.req.json(); } catch {
    return c.json({ error: "invalid json" }, 400);
  }
  const email = body.email ? normalizeEmail(body.email) : null;
  const otp = body.otp?.trim();
  const keyId = body.keyId;
  if (!email || !otp || !keyId) return c.json({ error: "email, otp and keyId are required" }, 400);

  if (!(await hasCloudEntitlement(c, managerToken))) {
    return c.json({ error: "cloud_tier_required" }, 403);
  }

  const result = await verifyOtp<{ email: string }>(c.env.FLAGS, registerOtpKey(managerToken), otp);
  if (!result.ok) return c.json({ error: result.error }, 401);
  if (result.payload.email !== email) return c.json({ error: "email mismatch" }, 401);

  const existing = await getAccountByEmail(c.env.DB, email);
  const accountUuid = existing?.accountUuid ?? crypto.randomUUID().toLowerCase();

  await upsertAccount(c.env.DB, { accountUuid, email, activeKeyId: keyId });
  await linkAccount(c.env.DB, { accountUuid, managerToken });

  return c.json({ ok: true });
});

// ─── Link device (new/lost phone, no attested identity yet) ─────────────────

// POST /account/link-device/request
// Body: { email }. Responds identically whether or not the email is known,
// to avoid enumeration — only actually sends an email when it is.
account.post("/link-device/request", async (c) => {
  let body: { email?: string };
  try { body = await c.req.json(); } catch {
    return c.json({ error: "invalid json" }, 400);
  }
  const email = body.email ? normalizeEmail(body.email) : null;
  if (!email) return c.json({ error: "email is required" }, 400);

  const managerTokens = await getManagerTokensByEmail(c.env.DB, email);
  if (managerTokens.length > 0) {
    const managerToken = managerTokens[0]!;
    const result = await issueOtp(c.env.FLAGS, linkDeviceOtpKey(email), { managerToken });
    if (!("error" in result)) {
      try {
        await sendOtpEmail(c.env, email, result.code);
      } catch (err) {
        console.error(JSON.stringify({ msg: "otp send failed", route: "link-device", error: String(err instanceof EmailSendError ? err.message : err) }));
      }
    }
    // Cooldown errors are also swallowed here — the generic response below
    // doesn't distinguish "already sent" from "unknown email" either.
  }

  return c.json({ ok: true });
});

// POST /account/link-device/verify
// Body: { email, otp }. On success, opens a pending-bind window and returns
// the manager_token — the client then runs the normal /attest/register flow
// with it, which is what actually claims active_key_id (see routes/attest.ts).
account.post("/link-device/verify", async (c) => {
  let body: { email?: string; otp?: string };
  try { body = await c.req.json(); } catch {
    return c.json({ error: "invalid json" }, 400);
  }
  const email = body.email ? normalizeEmail(body.email) : null;
  const otp = body.otp?.trim();
  if (!email || !otp) return c.json({ error: "email and otp are required" }, 400);

  const result = await verifyOtp<{ managerToken: string }>(c.env.FLAGS, linkDeviceOtpKey(email), otp);
  if (!result.ok) return c.json({ error: result.error }, 401);

  const { managerToken } = result.payload;
  await writePendingBind(c.env.FLAGS, managerToken);

  return c.json({ managerToken });
});
