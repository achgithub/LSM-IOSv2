import { Hono } from "hono";
import { requireAdmin } from "../auth";
import { FootballDataProvider } from "../football";
import { syncFixtures, syncStandings, syncTeams, warmScores } from "../sync";
import { getLeagueConfig } from "../types";

// Admin endpoint to trigger a provider sync on demand (ops / first seed),
// instead of waiting for the maintenance-window cron. Guarded by ADMIN_TOKEN.
//
//   POST /admin/sync?what=all|teams|fixtures|standings|scores
//   Authorization: Bearer <ADMIN_TOKEN>
//
// Safe to remove post-launch — the cron (§10.3) covers normal operation.
export const admin = new Hono<{ Bindings: Env }>();

admin.post("/sync", async (c) => {
  if (!requireAdmin(c.env, c.req.header("Authorization"))) {
    return c.json({ error: "unauthorized" }, 401);
  }

  const cfg = getLeagueConfig(c.env);
  const provider = new FootballDataProvider(
    c.env.FOOTBALL_DATA_TOKEN,
    cfg.footballDataCode,
    cfg.leagueId,
  );

  const what = c.req.query("what") ?? "all";
  const synced: Record<string, number> = {};
  // Teams first (fixtures + standings reference them).
  if (what === "all" || what === "teams") synced.teams = await syncTeams(c.env.DB, provider);
  if (what === "all" || what === "fixtures") synced.fixtures = await syncFixtures(c.env.DB, provider);
  if (what === "all" || what === "standings") synced.standings = await syncStandings(c.env.DB, provider);
  if (what === "all" || what === "scores") synced.scores = await warmScores(c.env.SCORES, provider);

  return c.json({ ok: true, synced });
});
