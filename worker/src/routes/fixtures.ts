import { Hono } from "hono";
import { getFixtures, type FixtureQuery } from "../db";
import { applyDemoToFixtures, getDemoClock } from "../demo";

// GET /fixtures?dateFrom=&dateTo=&matchday=
// All times ISO8601 UTC. With no params, returns all stored fixtures.
// When a demo clock is set, fixtures are re-timed/re-statused around "now"
// (date filters are ignored in demo mode; the matchday filter still applies).
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

  const q: FixtureQuery = {};
  const dateFrom = c.req.query("dateFrom");
  const dateTo = c.req.query("dateTo");
  if (dateFrom) q.dateFrom = dateFrom;
  if (dateTo) q.dateTo = dateTo;
  if (md !== undefined) q.matchday = md;
  return c.json(await getFixtures(c.env.DB, q));
});
