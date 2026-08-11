// LSM API v2 — standalone KV-backed authority Worker
//
// A new, separate Worker validating the KV-based sync design in isolation —
// NOT a replacement for worker-api (V1's live production Worker), which is
// untouched by this build. See wrangler.jsonc's header comment for scope.
//
// Owns:
//   • App Attest device registry + JWT issuance   /attest/*   (duplicated
//     as-is from worker-api — own D1 database, own JWT keypair)
//   • PWA submission queue (manager + player)     /links, /games/*, /s/*
//   • Manager lifecycle                           /manager/*
//
// No /admin/* (outage flag / ops endpoints) — intentionally not duplicated,
// out of scope for standing up the KV design (see wrangler.jsonc).

import { Hono } from "hono";
import { cors } from "hono/cors";
import { attest } from "./routes/attest";
import { manager } from "./routes/manager";
import { submissions } from "./routes/submissions";
import { requireJWT } from "./middleware/jwt";

const app = new Hono<{ Bindings: Env }>();

app.get("/", (c) => c.json({ service: "lsm-api-v2", region: c.env.REGION }));

app.get("/health", async (c) => {
  const row = await c.env.DB.prepare(
    "SELECT COUNT(*) AS n FROM attest_devices"
  ).first<{ n: number }>();
  return c.json({ ok: true, region: c.env.REGION, devices: row?.n ?? 0 });
});

// CORS for player-facing PWA routes (cross-origin from a submit.* origin) —
// registered before any gating middleware so a gate's short-circuit still
// ships CORS headers, same reasoning as worker-api's index.ts.
app.use("/s/*", cors({
  origin: "*",
  allowMethods: ["GET", "POST", "OPTIONS"],
  allowHeaders: ["Content-Type"],
}));

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

// Single submissions mount after middleware — /s/* stays public, everything else gated.
app.route("/", submissions);
app.route("/manager", manager);

app.notFound((c) => c.json({ error: "not found" }, 404));
app.onError((err, c) => {
  console.error(JSON.stringify({ msg: "unhandled error", error: String(err) }));
  return c.json({ error: "internal error" }, 500);
});

export default {
  fetch: app.fetch,
  // No `scheduled` export — retention is `expirationTtl` on every KV write,
  // enforced by Cloudflare itself. See kv/retention.ts.
} satisfies ExportedHandler<Env>;
