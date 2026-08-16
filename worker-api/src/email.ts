// Outbound transactional email via Resend — the only mail integration in
// this Worker. No SDK, just a single fetch(); Resend's REST API takes a
// plain JSON body and a Bearer API key.
//
// Requires UK_RESEND_API_KEY (set via `wrangler secret put UK_RESEND_API_KEY
// --env uk`) and a domain verified in the Resend dashboard — both are manual
// one-off setup steps, not part of this codebase.

import { regionSecret } from "./auth";

const FROM_ADDRESS = "LSM <no-reply@sportsmanager.site>";

export class EmailSendError extends Error {}

export async function sendOtpEmail(env: Env, email: string, code: string): Promise<void> {
  const apiKey = regionSecret(env, "RESEND_API_KEY");
  if (!apiKey) throw new EmailSendError("RESEND_API_KEY not configured");

  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from: FROM_ADDRESS,
      to: [email],
      subject: `Your LSM code: ${code}`,
      text: `Your verification code is ${code}. It expires in 10 minutes. If you didn't request this, you can ignore this email.`,
      html: `<p>Your verification code is <strong>${code}</strong>.</p><p>It expires in 10 minutes. If you didn't request this, you can ignore this email.</p>`,
    }),
  });

  if (!res.ok) {
    const body = await res.text().catch(() => "");
    console.error(JSON.stringify({ msg: "resend send failed", status: res.status, body }));
    throw new EmailSendError(`resend responded ${res.status}`);
  }
}
