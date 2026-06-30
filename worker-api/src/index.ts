// LSM API Authority Worker
//
// One deployment per region (--env uk | eu | …). Owns:
//   • App Attest device registry + JWT issuance   /attest/*
//   • PWA submission queue (manager + player)     /links, /games/*, /s/*
//   • Cloud backup                                /backup/*
//   • Manager lifecycle                           /manager/*
//   • Region migration stubs                      /manager/export, /manager/import
//
// Sports data shards (worker/) are NOT here — they stay in their own codebase
// and only verify the JWTs this Worker issues.

import { Hono } from "hono";
import { attest } from "./routes/attest";
import { backup } from "./routes/backup";
import { manager } from "./routes/manager";
import { submissions } from "./routes/submissions";
import { migrate } from "./routes/migrate";
import { requireJWT } from "./middleware/jwt";

const app = new Hono<{ Bindings: Env }>();

app.get("/", (c) => c.json({ service: "lsm-api", region: c.env.REGION }));

app.get("/health", async (c) => {
  const row = await c.env.DB.prepare(
    "SELECT COUNT(*) AS n FROM attest_devices"
  ).first<{ n: number }>();
  return c.json({ ok: true, region: c.env.REGION, devices: row?.n ?? 0 });
});

// ── Public ────────────────────────────────────────────────────────────────────

// Attest enrolment + JWT issuance.
app.route("/attest", attest);

// ── JWT-gated ─────────────────────────────────────────────────────────────────
// Middleware registered before any route mount so every matching path is covered.
// /s/* and /s/:token/games/* are deliberately absent — player PWA is browser-only.

app.use("/links", requireJWT);
app.use("/links/*", requireJWT);
app.use("/games/*", requireJWT);
app.use("/backup/*", requireJWT);
app.use("/manager/*", requireJWT);

// Single submissions mount after middleware — /s/* stays public, everything else gated.
app.route("/", submissions);
app.route("/backup", backup);
app.route("/manager", manager);
app.route("/manager", migrate); // /manager/export, /manager/import

app.notFound((c) => c.json({ error: "not found" }, 404));
app.onError((err, c) => {
  console.error(JSON.stringify({ msg: "unhandled error", error: String(err) }));
  return c.json({ error: "internal error" }, 500);
});

export default { fetch: app.fetch } satisfies ExportedHandler<Env>;
