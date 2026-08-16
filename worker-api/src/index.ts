// LSM API Authority Worker
//
// One deployment per region (--env uk | eu | …). Owns:
//   • App Attest device registry + JWT issuance   /attest/*
//   • PWA submission queue (manager + player)     /links, /games/*, /s/*
//   • Manager lifecycle + per-game sync            /manager/*
//   • Email registration + device recovery        /account/*
//   • Region migration stubs                      /manager/export, /manager/import
//   • Global outage flag (ops-only)                /admin/outage
//
// Sports data shards (worker/) are NOT here — they stay in their own codebase
// and only verify the JWTs this Worker issues.
//
// Cloud Backup (/backup/*) and Cloud Publish (/publish, /publish/:id/unlock)
// were removed 2026-08-02 — R2 dependency being shed ahead of launch. Publish
// was already unreachable from any app UI; Backup is being replaced by
// /account/* (identity only, not game data) plus /manager/games/* for
// per-game sync — see routes/account.ts's header comment for how the two
// fit together.

import { Hono } from "hono";
import { cors } from "hono/cors";
import { admin } from "./routes/admin";
import { attest } from "./routes/attest";
import { account } from "./routes/account";
import { manager } from "./routes/manager";
import { submissions } from "./routes/submissions";
import { migrate } from "./routes/migrate";
import { requireJWT } from "./middleware/jwt";
import { outageGate } from "./middleware/outage";
import { runDailyCleanup } from "./cron";

const app = new Hono<{ Bindings: Env }>();

app.get("/", (c) => c.json({ service: "lsm-api", region: c.env.REGION }));

app.get("/health", async (c) => {
  const row = await c.env.DB.prepare(
    "SELECT COUNT(*) AS n FROM attest_devices"
  ).first<{ n: number }>();
  return c.json({ ok: true, region: c.env.REGION, devices: row?.n ?? 0 });
});

// CORS for player-facing PWA routes (cross-origin from submit.sportsmanager.site)
// must be registered before the outage gate, not inside routes/submissions.ts —
// Hono composes middleware in registration order, so a 503 short-circuit from
// the gate below would otherwise ship with no Access-Control-Allow-Origin
// header and the browser would surface it as an opaque network failure
// instead of a readable maintenance response.
app.use("/s/*", cors({
  origin: "https://submit.sportsmanager.site",
  allowMethods: ["GET", "POST", "OPTIONS"],
  allowHeaders: ["Content-Type"],
}));

// Global outage gate — bypasses /health and /admin/* so ops tooling and the
// toggle itself never lock out. See middleware/outage.ts.
app.use("*", outageGate);

app.route("/admin", admin);

// ── Public ────────────────────────────────────────────────────────────────────

// Attest enrolment + JWT issuance.
app.route("/attest", attest);

// ── JWT-gated ─────────────────────────────────────────────────────────────────
// Middleware registered before any route mount so every matching path is covered.
// /s/* and /s/:token/games/* are deliberately absent — player PWA is browser-only.

app.use("/links", requireJWT);
app.use("/links/*", requireJWT);
app.use("/games/*", requireJWT);
app.use("/manager/*", requireJWT);
// Only the already-live-device half of /account/* is gated — /account/link-device/*
// stays public below, same as /attest/register (a device with no JWT yet is exactly
// who needs it).
app.use("/account/register", requireJWT);
app.use("/account/verify", requireJWT);

// Single submissions mount after middleware — /s/* stays public, everything else gated.
app.route("/", submissions);
app.route("/manager", manager);
app.route("/manager", migrate); // /manager/export, /manager/import
app.route("/account", account);

app.notFound((c) => c.json({ error: "not found" }, 404));
app.onError((err, c) => {
  console.error(JSON.stringify({ msg: "unhandled error", error: String(err) }));
  return c.json({ error: "internal error" }, 500);
});

export default {
  fetch: app.fetch,
  // Cron scheduled handler — NOT activated yet (#12 parked until current test
  // cycle finishes). Activate by setting triggers.crons in wrangler.jsonc,
  // e.g. "0 3 * * *" for a 3am UTC daily run.
  scheduled: async (_ctrl: ScheduledController, env: Env, _ctx: ExecutionContext) => {
    await runDailyCleanup(env);
  },
} satisfies ExportedHandler<Env>;
