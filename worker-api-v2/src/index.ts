// LSM API v2 — standalone KV-backed authority Worker
//
// A new, separate Worker validating the KV-based sync design in isolation —
// NOT a replacement for worker-api (V1's live production Worker), which is
// untouched by this build. See wrangler.jsonc's header comment for scope.
//
// Owns:
//   • PWA submission queue (manager + player)     /links, /games/*, /s/*
//   • Manager lifecycle                           /manager/*
//
// Does NOT own App Attest / JWT issuance — worker-api is the identity
// authority (it owns the device registry and signs JWTs). This Worker only
// *verifies* JWTs worker-api issued (jwt.ts + middleware/jwt.ts), the same
// pattern the sports-data shards (worker/) already use to trust worker-api
// without duplicating its authority role. There is no D1 database here at
// all — pure KV.
//
// No /admin/* (outage flag / ops endpoints) — intentionally not duplicated,
// out of scope for standing up the KV design (see wrangler.jsonc).

import { Hono } from "hono";
import { cors } from "hono/cors";
import { manager } from "./routes/manager";
import { submissions } from "./routes/submissions";
import { requireJWT } from "./middleware/jwt";

const app = new Hono<{ Bindings: Env }>();

app.get("/", (c) => c.json({ service: "lsm-api-v2", region: c.env.REGION }));

// No D1 here to count against — this Worker is pure KV. A real liveness
// check would ping SUBMISSIONS_KV, but KV has no cheap "is it up" query
// analogous to D1's COUNT(*); presence of a 200 response is the check.
app.get("/health", (c) => c.json({ ok: true, region: c.env.REGION }));

// CORS for player-facing PWA routes (cross-origin from a submit.* origin) —
// registered before any gating middleware so a gate's short-circuit still
// ships CORS headers, same reasoning as worker-api's index.ts.
app.use("/s/*", cors({
  origin: "*",
  allowMethods: ["GET", "POST", "OPTIONS"],
  allowHeaders: ["Content-Type"],
}));

// ── JWT-gated ─────────────────────────────────────────────────────────────────
// Middleware registered before any route mount so every matching path is covered.
// /s/* and /s/:token/games/* are deliberately absent — player PWA is browser-only.
// JWTs are minted by worker-api's /attest/* flow, never here — see this
// file's header comment and jwt.ts.

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
