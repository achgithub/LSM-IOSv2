import { Hono } from "hono";
import { requireAdmin } from "../auth";
import { FootballDataProvider } from "../football";
import { refreshMatchData, refreshStandings } from "../refresh";
import { syncTeams } from "../sync";
import { getLeagueConfig } from "../types";

// Admin endpoint to trigger a provider sync on demand (ops / first seed),
// instead of waiting for the maintenance-window cron. Guarded by ADMIN_TOKEN.
//
//   POST /admin/sync?what=all|teams|fixtures|standings|scores
//   Authorization: Bearer <ADMIN_TOKEN>
//
// Note: scores + fixtures share one upstream (/matches), so what=fixtures and
// what=scores both run the single combined match refresh (and report both counts).
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
  if (what === "all" || what === "fixtures" || what === "scores") {
    const m = await refreshMatchData(c.env.DB, c.env.SCORES, provider);
    synced.fixtures = m.fixtures;
    synced.scores = m.scores;
  }
  if (what === "all" || what === "standings") {
    synced.standings = await refreshStandings(c.env.DB, provider);
  }

  return c.json({ ok: true, synced });
});
