import { Hono } from "hono";
import {
  getAccountByEmail,
  getManagerTokensByEmail,
  upsertAccount,
  linkAccount,
} from "../account-store";
import { issueOtp, verifyOtp, registerOtpKey, linkDeviceOtpKey, writePendingBind } from "../otp";
import { sendOtpEmail, EmailSendError } from "../email";

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
// Not shard-routed — queried via c.env.DB directly, same as the admin
// device-management routes. See schema.sql's comment on accounts for why.

export const account = new Hono<{ Bindings: Env }>();

function managerTokenHeader(c: { req: { header: (name: string) => string | undefined } }): string | null {
  return c.req.header("X-Manager-Token")?.toLowerCase() ?? null;
}

function normalizeEmail(email: string): string {
  return email.trim().toLowerCase();
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
