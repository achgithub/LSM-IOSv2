// Outbound transactional email via Resend — the only mail integration in
// this Worker. No SDK, just a single fetch(); Resend's REST API takes a
// plain JSON body and a Bearer API key.
//
// Requires UK_RESEND_API_KEY (set via `wrangler secret put UK_RESEND_API_KEY
// --env uk`) and a domain verified in the Resend dashboard — both are manual
// one-off setup steps, not part of this codebase.

import { regionSecret } from "./auth";

const FROM_ADDRESS = "LSM <no-reply@sportsmanager.site>";

// Matches Brand.accent in the iOS app (Shared/Splash/SplashView.swift) —
// LMS's own accent colour, not Brand.sharedBlue (that one's shared across
// the whole app family, used for the splash wordmark, not this app's UI).
const ACCENT = "#F97316";

export class EmailSendError extends Error {}

function otpEmailText(code: string): string {
  return `Your verification code is ${code}.\n\nIt expires in 10 minutes. If you didn't request this, you can ignore this email.`;
}

// Plain inline-styled HTML, no external assets/fonts/images — the safest
// baseline for both deliverability and rendering consistency across email
// clients (notably Outlook desktop, which ignores most modern CSS).
function otpEmailHtml(code: string): string {
  const spacedCode = code.split("").join(" ");
  return `<!doctype html>
<html>
  <body style="margin:0; padding:24px 16px; background-color:#f2f2f2; font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:420px; margin:0 auto; background-color:#ffffff; border-radius:12px; overflow:hidden;">
      <tr>
        <td style="padding:28px 32px 8px 32px; text-align:center;">
          <div style="font-size:20px; font-weight:700; color:${ACCENT}; letter-spacing:0.5px;">LSM</div>
        </td>
      </tr>
      <tr>
        <td style="padding:8px 32px 0 32px; text-align:center; color:#1a1a1a;">
          <p style="margin:0 0 20px 0; font-size:15px; line-height:1.5;">Your verification code is:</p>
        </td>
      </tr>
      <tr>
        <td style="padding:0 32px; text-align:center;">
          <div style="display:inline-block; padding:14px 22px; background-color:#fff4ec; border:1px solid ${ACCENT}; border-radius:8px; font-size:28px; font-weight:700; letter-spacing:4px; color:${ACCENT}; font-family:'SF Mono',Menlo,Consolas,monospace;">${spacedCode}</div>
        </td>
      </tr>
      <tr>
        <td style="padding:20px 32px 28px 32px; text-align:center;">
          <p style="margin:0; font-size:13px; line-height:1.5; color:#6b6b6b;">
            This code expires in 10 minutes. If you didn't request it, you can safely ignore this email.
          </p>
        </td>
      </tr>
    </table>
  </body>
</html>`;
}

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
      text: otpEmailText(code),
      html: otpEmailHtml(code),
    }),
  });

  if (!res.ok) {
    const body = await res.text().catch(() => "");
    console.error(JSON.stringify({ msg: "resend send failed", status: res.status, body }));
    throw new EmailSendError(`resend responded ${res.status}`);
  }
}
