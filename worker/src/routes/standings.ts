import { Hono } from "hono";
import { getFixtures, getStandings, getTeams } from "../db";
import { demoStandings, demoClockIfEnabled } from "../demo";
import { FootballDataProvider } from "../football";
import { STANDINGS_KEYS, withFreshness } from "../gate";
import { refreshStandings } from "../refresh";
import { currentSeasonYear } from "../seasonPhase";
import { getLeagueConfig } from "../types";

// GET /standings — full league table, ordered by position. Request-triggered:
// past the standings TTL a request refreshes /standings in the background and
// serves the current D1 table immediately (stale-while-revalidate). When a demo
// clock is set, the table is computed from results up to the demo clock.
export const standings = new Hono<{ Bindings: Env }>();

standings.get("/", async (c) => {
  const clock = await demoClockIfEnabled(c.env);
  if (clock) {
    const [fixtures, teams] = await Promise.all([getFixtures(c.env.DB), getTeams(c.env.DB)]);
    return c.json(demoStandings(fixtures, teams, clock));
  }

  const cfg = getLeagueConfig(c.env);
  const provider = new FootballDataProvider(
    c.env.FOOTBALL_DATA_TOKEN,
    cfg.footballDataCode,
    cfg.leagueId,
  );
  await withFreshness(
    c.env.SCORES,
    STANDINGS_KEYS,
    cfg.standingsTtlMs,
    async () => refreshStandings(c.env.DB, provider, await currentSeasonYear(c.env.DB)),
    c.executionCtx,
  );
  return c.json(await getStandings(c.env.DB));
});
