import { Hono } from "hono";
import { getFixtures } from "../db";
import { demoScores, demoClockIfEnabled } from "../demo";
import { FootballDataProvider } from "../football";
import { SCORES_DATA_KEY, SCORES_KEYS, withFreshness } from "../gate";
import { refreshMatchData } from "../refresh";
import { getLeagueConfig, type ScoreEntry } from "../types";

// GET /scores
// One shared cache for everyone — free vs subscriber is not a freshness tier;
// the app gates the refresh action behind a rewarded ad for free users. Stale
// data is served immediately and refreshed in the background (spec §10.2). The
// refresh fetches /matches, which co-warms the fixtures cache too.
// When a demo clock is set, returns the current matchday's (synthetic) scores.
export const scores = new Hono<{ Bindings: Env }>();

scores.get("/", async (c) => {
  const clock = await demoClockIfEnabled(c.env);
  if (clock) {
    return c.json(demoScores(await getFixtures(c.env.DB), clock));
  }

  const cfg = getLeagueConfig(c.env);
  const provider = new FootballDataProvider(
    c.env.FOOTBALL_DATA_TOKEN,
    cfg.footballDataCode,
    cfg.leagueId,
  );
  await withFreshness(
    c.env.SCORES,
    SCORES_KEYS,
    cfg.scoreTtlMs,
    () => refreshMatchData(c.env.DB, c.env.SCORES, provider),
    c.executionCtx,
  );
  const cached = await c.env.SCORES.get(SCORES_DATA_KEY);
  return c.json(cached ? (JSON.parse(cached) as ScoreEntry[]) : []);
});
