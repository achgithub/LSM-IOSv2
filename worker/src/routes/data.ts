import { Hono } from "hono";
import {
  getAllLeagues,
  getFixturesByLeague,
  getLeagueRow,
  getScoresByLeague,
  getStandingsByLeague,
  getTeamsByLeague,
  type FixtureQuery,
  type LeagueRow,
} from "../db";
import { regionSecret } from "../auth";
import { FootballDataProvider } from "../football";
import { leagueKeys, withFreshness } from "../gate";
import { buildManifest } from "../manifest";
import { requireJWT } from "../middleware/jwt";
import { refreshMatchData, refreshStandings } from "../refresh";
import { currentSeasonYear, getSeasonPhase } from "../seasonPhase";
import type { ScoreEntry } from "../types";

// ── v2 app↔DB read path (Layer 1, multi-league shard) ────────────────────────
// Replaces v1's single-league /fixtures /scores /standings /teams.
//
// Request-triggered freshness (stale-while-revalidate) is identical to v1:
//   • scores + fixtures share one /matches upstream call, co-warm each other
//   • standings have their own /standings call
// The only v2 difference: keys and DB writes are league-scoped.
//
// Middleware fetches the full league row once so handlers have TTL values +
// football_data_code without extra queries.

type Vars = { league: LeagueRow };

export const data = new Hono<{ Bindings: Env; Variables: Vars }>();

// League discovery — full manifest so the app finds every shard's leagues.
data.get("/leagues.json", async (c) => {
  // Augment the static manifest with live shard data (league count from DB).
  const manifest = buildManifest();
  return c.json(manifest);
});

// Per-league middleware: verify the league is in this shard, fetch its config.
data.use("/leagues/:leagueId/*", async (c, next) => {
  const row = await getLeagueRow(c.env.DB, c.req.param("leagueId"));
  if (!row) return c.json({ error: "league not served by this shard" }, 404);
  c.set("league", row);
  await next();
});

// Teams — attest-gated (upstream data license requires all league data to be
// protected from unauthenticated/general access, not just scores/fixtures).
data.use("/leagues/:leagueId/teams", requireJWT);
data.get("/leagues/:leagueId/teams", async (c) =>
  c.json(await getTeamsByLeague(c.env.DB, c.req.param("leagueId"))),
);

// Standings — attest-gated, same license requirement as teams above.
data.use("/leagues/:leagueId/standings", requireJWT);
data.get("/leagues/:leagueId/standings", async (c) => {
  const league = c.get("league");
  const keys = leagueKeys(league.id);
  if ((await getSeasonPhase(c.env.SCORES, league.id)) === "live") {
    const provider = new FootballDataProvider(regionSecret(c.env, "FOOTBALL_DATA_TOKEN"), league.football_data_code, league.id);
    await withFreshness(
      c.env.SCORES, keys.standings, league.standings_ttl_seconds * 1000,
      async () => refreshStandings(c.env.DB, provider, await currentSeasonYear(c.env.DB, league.id), league.id),
      c.executionCtx,
    );
  }
  return c.json(await getStandingsByLeague(c.env.DB, league.id));
});

// Scores — attest-gated, backed by KV cache (same as v1 /scores).
data.use("/leagues/:leagueId/scores", requireJWT);
data.get("/leagues/:leagueId/scores", async (c) => {
  const league = c.get("league");
  const keys = leagueKeys(league.id);
  if ((await getSeasonPhase(c.env.SCORES, league.id)) === "live") {
    const provider = new FootballDataProvider(regionSecret(c.env, "FOOTBALL_DATA_TOKEN"), league.football_data_code, league.id);
    await withFreshness(
      c.env.SCORES, keys.scores, league.score_ttl_seconds * 1000,
      async () => refreshMatchData(c.env.DB, c.env.SCORES, provider, await currentSeasonYear(c.env.DB, league.id), league.id),
      c.executionCtx,
    );
  }
  const cached = await c.env.SCORES.get(keys.scoresData);
  // Fall back to D1-derived scores if KV not yet populated (first run).
  if (cached) return c.json(JSON.parse(cached) as ScoreEntry[]);
  return c.json(await getScoresByLeague(c.env.DB, league.id));
});

// Fixtures — attest-gated, co-warmed when scores gate fires.
data.use("/leagues/:leagueId/fixtures", requireJWT);
data.get("/leagues/:leagueId/fixtures", async (c) => {
  const league = c.get("league");
  const keys = leagueKeys(league.id);
  if ((await getSeasonPhase(c.env.SCORES, league.id)) === "live") {
    const provider = new FootballDataProvider(regionSecret(c.env, "FOOTBALL_DATA_TOKEN"), league.football_data_code, league.id);
    await withFreshness(
      c.env.SCORES, keys.fixtures, league.fixtures_ttl_seconds * 1000,
      async () => refreshMatchData(c.env.DB, c.env.SCORES, provider, await currentSeasonYear(c.env.DB, league.id), league.id),
      c.executionCtx,
    );
  }
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
  return c.json(await getFixturesByLeague(c.env.DB, league.id, q));
});

// Admin convenience: list all leagues in this shard (public metadata only).
data.get("/leagues", async (c) => {
  const leagues = await getAllLeagues(c.env.DB);
  return c.json(leagues.map((l) => ({ id: l.id, name: l.name, region: l.region, status: l.status })));
});
