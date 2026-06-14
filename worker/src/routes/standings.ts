import { Hono } from "hono";
import { getFixtures, getStandings, getTeams } from "../db";
import { demoStandings, getDemoClock } from "../demo";

// GET /standings — full league table, ordered by position. When a demo clock is
// set, the table is computed from results up to the demo clock (mid-season).
export const standings = new Hono<{ Bindings: Env }>();

standings.get("/", async (c) => {
  const clock = await getDemoClock(c.env.SCORES);
  if (clock) {
    const [fixtures, teams] = await Promise.all([getFixtures(c.env.DB), getTeams(c.env.DB)]);
    return c.json(demoStandings(fixtures, teams, clock));
  }
  return c.json(await getStandings(c.env.DB));
});
