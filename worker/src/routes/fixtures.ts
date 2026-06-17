import { Hono } from "hono";
import { getFixtures, type FixtureQuery } from "../db";
import { applyDemoToFixtures, getDemoClock } from "../demo";
import { FootballDataProvider } from "../football";
import { FIXTURES_KEYS, withFreshness } from "../gate";
import { refreshMatchData } from "../refresh";
import { getLeagueConfig } from "../types";

// GET /fixtures?dateFrom=&dateTo=&matchday=
// All times ISO8601 UTC. With no params, returns all stored fixtures.
// Request-triggered like /scores: past the fixtures TTL a request refreshes
// /matches in the background (co-warming scores) and serves the current D1 data
// immediately. When a demo clock is set, fixtures are re-timed/re-statused around
// "now" (date filters are ignored in demo mode; the matchday filter still applies).
export const fixtures = new Hono<{ Bindings: Env }>();

fixtures.get("/", async (c) => {
  const matchday = c.req.query("matchday");
  let md: number | undefined;
  if (matchday !== undefined) {
    const n = Number(matchday);
    if (!Number.isInteger(n)) return c.json({ error: "matchday must be an integer" }, 400);
    md = n;
  }

  const clock = await getDemoClock(c.env.SCORES);
  if (clock) {
    let data = applyDemoToFixtures(await getFixtures(c.env.DB), clock);
    if (md !== undefined) data = data.filter((f) => f.matchday === md);
    return c.json(data);
  }

  const cfg = getLeagueConfig(c.env);
  const provider = new FootballDataProvider(
    c.env.FOOTBALL_DATA_TOKEN,
    cfg.footballDataCode,
    cfg.leagueId,
  );
  await withFreshness(
    c.env.SCORES,
    FIXTURES_KEYS,
    cfg.fixturesTtlMs,
    () => refreshMatchData(c.env.DB, c.env.SCORES, provider),
    c.executionCtx,
  );

  const q: FixtureQuery = {};
  const dateFrom = c.req.query("dateFrom");
  const dateTo = c.req.query("dateTo");
  if (dateFrom) q.dateFrom = dateFrom;
  if (dateTo) q.dateTo = dateTo;
  if (md !== undefined) q.matchday = md;
  return c.json(await getFixtures(c.env.DB, q));
});
