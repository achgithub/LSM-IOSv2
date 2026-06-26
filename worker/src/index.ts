// LSM v2 Worker — regional-shard API for cloud-backed game state + sports data.
//
// One deployment per region shard (--env uk | eu). Each shard's D1 holds many
// leagues (rows in the `leagues` table). Two surfaces:
//   • Layer 1 (./routes/data): the app↔DB read path — /leagues/:id/{teams,
//     fixtures,standings,scores} + /leagues.json discovery, served straight off
//     the seeded shard. NO upstream football-data.org call here (that sync is a
//     separate, deferred concern; the v1 sync machinery is kept dormant in
//     football.ts/refresh.ts/sync.ts for when it's built).
//   • Layer 2 (./routes/{games,submissions}): cloud-backed game state + the
//     anonymous PWA submission queue (skeletons).
//
// See docs/lsm-v2-architecture.md.

import { Hono } from "hono";
import { backup } from "./routes/backup";
import { attest } from "./routes/attest";
import { runDailyCleanup } from "./cron";
import { data } from "./routes/data";
import { games } from "./routes/games";
import { manager } from "./routes/manager";
import { publish } from "./routes/publish";
import { submissions } from "./routes/submissions";
import { requireAttestation } from "./middleware/attest";

const app = new Hono<{ Bindings: Env }>();

app.get("/", (c) => c.json({ service: "lsm-worker" }));

app.get("/health", async (c) => {
  const row = await c.env.DB.prepare("SELECT COUNT(*) AS n FROM leagues").first<{ n: number }>();
  return c.json({ ok: true, leagues: row?.n ?? 0 });
});

// Layer 1 — read path + league discovery (/leagues.json, /leagues/:id/*).
// Attestation is enforced inside data.ts for /leagues/:id/scores and /leagues/:id/fixtures;
// /leagues.json, /leagues/:id/teams, and /leagues/:id/standings remain public.
app.route("/", data);

// Layer 2 — cloud-backed game state + the anonymous submission queue.
app.route("/games", games); // manager-facing (LSM app)
app.route("/", submissions); // /s/:token (player PWA) + /submissions/* (manager)

// Attest enrolment — public (no assertion required; this is how clients register).
app.route("/attest", attest);

// Cloud bundle (Phase 2) — R2 blob snapshots. Attest-gated; /publish/:id/unlock
// (viewer PIN check) stays public and is NOT covered by the wildcard below.
app.use("/backup/*", requireAttestation);
app.route("/backup", backup);

app.use("/publish", requireAttestation); // POST /publish only; /publish/:id/unlock is public
app.route("/publish", publish);

// Phase 6 — manager lifecycle. Attest-gated so only the genuine app can
// trigger subscription events or schedule data deletion.
app.use("/manager/*", requireAttestation);
app.route("/manager", manager);

app.notFound((c) => c.json({ error: "not found" }, 404));
app.onError((err, c) => {
  console.error(JSON.stringify({ msg: "unhandled error", error: String(err) }));
  return c.json({ error: "internal error" }, 500);
});

export default {
  fetch: app.fetch,
  // Daily cleanup cron — handler is built but the trigger is NOT active yet.
  // To activate: add "0 3 * * *" to wrangler.jsonc triggers.crons for each env.
  scheduled: async (_ctrl: ScheduledController, env: Env, _ctx: ExecutionContext) => {
    await runDailyCleanup(env);
  },
} satisfies ExportedHandler<Env>;
