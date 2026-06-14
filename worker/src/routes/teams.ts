import { Hono } from "hono";
import { getTeams } from "../db";

// GET /teams — the league's clubs. Not in the original spec endpoint list, but
// the app needs it to resolve the team ids referenced by fixtures/scores into
// names. Visual identity (colours/abbrev) is bundled app-side per §15.
export const teams = new Hono<{ Bindings: Env }>();

teams.get("/", async (c) => {
  const data = await getTeams(c.env.DB);
  return c.json(data);
});
