import { Hono } from "hono";
import { getFixtures } from "../db";
import { demoScores, getDemoClock } from "../demo";
import { FootballDataProvider } from "../football";
import { getScores } from "../scores";
import { getLeagueConfig, type Tier } from "../types";

// GET /scores?tier=free|sub
// Trust-on-client (spec §10.2): the only difference is freshness, not gated
// content. Defaults to the free (stale) tier when tier is missing/unknown.
// When a demo clock is set, returns the current matchday's (synthetic) scores.
export const scores = new Hono<{ Bindings: Env }>();

scores.get("/", async (c) => {
  const clock = await getDemoClock(c.env.SCORES);
  if (clock) {
    return c.json(demoScores(await getFixtures(c.env.DB), clock));
  }

  const tier: Tier = c.req.query("tier") === "sub" ? "sub" : "free";
  const cfg = getLeagueConfig(c.env);
  const provider = new FootballDataProvider(
    c.env.FOOTBALL_DATA_TOKEN,
    cfg.footballDataCode,
    cfg.leagueId,
  );
  const data = await getScores(
    c.env.SCORES,
    tier,
    cfg.scoreTtlMs[tier],
    () => provider.fetchScores(),
    c.executionCtx,
  );
  return c.json(data);
});
