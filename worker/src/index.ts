// LSM v2 Worker — regional-shard API for cloud-backed game state + sports data.
//
// One deployment per region shard (--env uk | eu). Each shard's D1 holds many
// leagues (rows in the `leagues` table). Two surfaces:
//   • Layer 1 (./routes/data): the app↔DB read path — /leagues/:id/{teams,
//     fixtures,standings,scores} + /leagues.json discovery. Request-triggered
//     stale-while-revalidate (same gate.ts pattern as v1) keeps football-data.org
//     calls TTL-limited.
//   • Layer 2 (./routes/{games,submissions}): cloud-backed game state + the
//     anonymous PWA submission queue.
//
// See docs/lsm-v2-architecture.md.

import { Hono } from "hono";
import { admin } from "./routes/admin";
import { runDailyCleanup, runDailySync } from "./cron";
import { data } from "./routes/data";
import { outageGate } from "./outage";
// Sports data shard — league discovery + read-only data (teams, fixtures,
// standings, scores). All lifecycle, backup, submissions, publish and attest
// now live in the regional authority Worker (worker-api/). JWT verification
// for /scores and /fixtures is applied inside data.ts via requireJWT.

const app = new Hono<{ Bindings: Env }>();

app.get("/", (c) => c.json({ service: "lsm-worker", region: c.env.SHARD_REGION }));

app.get("/health", async (c) => {
  const row = await c.env.DB.prepare("SELECT COUNT(*) AS n FROM leagues").first<{ n: number }>();
  return c.json({ ok: true, leagues: row?.n ?? 0 });
});

// Global outage gate — bypasses /health and /admin/* so ops tooling and the
// toggle itself never lock out. See outage.ts.
app.use("*", outageGate);

// Layer 1 — league discovery + read-only sports data.
// /teams, /standings, /scores, /fixtures are all JWT-gated (requireJWT
// applied inside data.ts) — upstream data license requires all league data
// protected from unauthenticated access. Only /leagues.json (manifest) and
// /leagues (metadata) remain public.
app.route("/", data);

// Admin — ops endpoints (sync, probe). Auth is inside admin.ts.
app.route("/admin", admin);

app.notFound((c) => c.json({ error: "not found" }, 404));
app.onError((err, c) => {
  console.error(JSON.stringify({ msg: "unhandled error", error: String(err) }));
  return c.json({ error: "internal error" }, 500);
});

export default {
  fetch: app.fetch,
  // Cron scheduled handler — activate by setting triggers.crons in wrangler.jsonc,
  // e.g. "0 4 * * *" for the uk shard, "0 2 * * *" for eu (match MAINTENANCE_WINDOW_UTC).
  scheduled: async (_ctrl: ScheduledController, env: Env, _ctx: ExecutionContext) => {
    await runDailyCleanup(env);
    await runDailySync(env);
  },
} satisfies ExportedHandler<Env>;
