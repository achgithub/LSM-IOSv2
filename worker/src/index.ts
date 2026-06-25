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
import { data } from "./routes/data";
import { games } from "./routes/games";
import { submissions } from "./routes/submissions";

const app = new Hono<{ Bindings: Env }>();

app.get("/", (c) => c.json({ service: "lsm-worker" }));

app.get("/health", async (c) => {
  const row = await c.env.DB.prepare("SELECT COUNT(*) AS n FROM leagues").first<{ n: number }>();
  return c.json({ ok: true, leagues: row?.n ?? 0 });
});

// Layer 1 — read path + league discovery (/leagues.json, /leagues/:id/*).
app.route("/", data);

// Layer 2 — cloud-backed game state + the anonymous submission queue.
app.route("/games", games); // manager-facing (LSM app)
app.route("/", submissions); // /s/:token (player PWA) + /submissions/* (manager)

// Cloud bundle (Phase 2) — R2 blob snapshots, not Layer-2 D1 state.
app.route("/backup", backup);

app.notFound((c) => c.json({ error: "not found" }, 404));
app.onError((err, c) => {
  console.error(JSON.stringify({ msg: "unhandled error", error: String(err) }));
  return c.json({ error: "internal error" }, 500);
});

export default {
  fetch: app.fetch,
} satisfies ExportedHandler<Env>;
