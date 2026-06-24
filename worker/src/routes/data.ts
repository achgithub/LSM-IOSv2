import { Hono } from "hono";
import {
  getFixturesByLeague,
  getScoresByLeague,
  getStandingsByLeague,
  getTeamsByLeague,
  leagueExists,
  type FixtureQuery,
} from "../db";
import { buildManifest } from "../manifest";

// ── v2 app↔DB read path (Layer 1, multi-league shard) ────────────────────────
// Replaces v1's single-league /fixtures /scores /standings /teams. A shard holds
// many leagues, so each read is scoped to /leagues/:leagueId/... and reads
// straight from the seeded shard — NO upstream football-data call (that sync is
// deferred). The JSON shapes are unchanged from v1, so the app decodes them as-is.
export const data = new Hono<{ Bindings: Env }>();

// League discovery — same manifest shape the app bundles. The app's registry
// refresh points here (v2) instead of v1's deleted registry worker.
data.get("/leagues.json", (c) => c.json(buildManifest()));

// Guard: the league must be one this shard actually serves.
data.use("/leagues/:leagueId/*", async (c, next) => {
  if (!(await leagueExists(c.env.DB, c.req.param("leagueId")))) {
    return c.json({ error: "league not served by this shard" }, 404);
  }
  await next();
});

data.get("/leagues/:leagueId/teams", async (c) =>
  c.json(await getTeamsByLeague(c.env.DB, c.req.param("leagueId"))),
);

data.get("/leagues/:leagueId/standings", async (c) =>
  c.json(await getStandingsByLeague(c.env.DB, c.req.param("leagueId"))),
);

data.get("/leagues/:leagueId/scores", async (c) =>
  c.json(await getScoresByLeague(c.env.DB, c.req.param("leagueId"))),
);

data.get("/leagues/:leagueId/fixtures", async (c) => {
  const q: FixtureQuery = {};
  const md = c.req.query("matchday");
  if (md !== undefined) {
    const n = Number(md);
    if (!Number.isInteger(n)) return c.json({ error: "matchday must be an integer" }, 400);
    q.matchday = n;
  }
  const dateFrom = c.req.query("dateFrom");
  const dateTo = c.req.query("dateTo");
  if (dateFrom) q.dateFrom = dateFrom;
  if (dateTo) q.dateTo = dateTo;
  return c.json(await getFixturesByLeague(c.env.DB, c.req.param("leagueId"), q));
});
