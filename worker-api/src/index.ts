// LSM API Authority Worker
//
// One deployment per region (--env uk | eu | …). Owns:
//   • App Attest device registry + JWT issuance   /attest/*
//   • PWA submission queue (manager + player)     /links, /games/*, /s/*
//   • Cloud backup                                /backup/*
//   • Manager lifecycle                           /manager/*
//   • Region migration stubs                      /manager/export, /manager/import
//   • Global outage flag (ops-only)                /admin/outage
//
// Sports data shards (worker/) are NOT here — they stay in their own codebase
// and only verify the JWTs this Worker issues.

import { Hono } from "hono";
import { cors } from "hono/cors";
import { admin } from "./routes/admin";
import { attest } from "./routes/attest";
import { backup } from "./routes/backup";
import { manager } from "./routes/manager";
import { publish } from "./routes/publish";
import { submissions } from "./routes/submissions";
import { migrate } from "./routes/migrate";
import { requireJWT } from "./middleware/jwt";
import { outageGate } from "./middleware/outage";

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

app.use("/publish", requireJWT);   // write path only — /:id/unlock stays public
app.use("/publish/:id", requireJWT);   // DELETE (unpublish) — /:id/unlock is a distinct path, unaffected
app.use("/links", requireJWT);
app.use("/links/*", requireJWT);
app.use("/games/*", requireJWT);
app.use("/backup/*", requireJWT);
app.use("/manager/*", requireJWT);

// Single submissions mount after middleware — /s/* stays public, everything else gated.
app.route("/", submissions);
app.route("/publish", publish);
app.route("/backup", backup);
app.route("/manager", manager);
app.route("/manager", migrate); // /manager/export, /manager/import

app.notFound((c) => c.json({ error: "not found" }, 404));
app.onError((err, c) => {
  console.error(JSON.stringify({ msg: "unhandled error", error: String(err) }));
  return c.json({ error: "internal error" }, 500);
});

export default { fetch: app.fetch } satisfies ExportedHandler<Env>;
