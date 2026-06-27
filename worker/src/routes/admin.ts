// Admin endpoints — v2 multi-league edition.
// Mechanically identical to v1 (probe, on-demand sync, phase flag, sync-if-due)
// with two v2 differences:
//   1. `?league=PL` selects which league to operate on (replaces per-worker scoping).
//   2. League config (football_data_code, TTLs) comes from the D1 leagues table
//      instead of env vars.
//
//   POST /admin/sync?league=PL&what=all|teams|fixtures|standings&season=YYYY
//   GET  /admin/probe-standings?league=PL&season=YYYY
//   POST /admin/sync-if-due            (OPS_SYNC_TOKEN — orchestrator)
//   GET  /admin/phase?league=PL
//   POST /admin/phase?league=PL&value=live|closed
//   GET  /admin/leagues
//   Authorization: Bearer <ADMIN_TOKEN>  (or OPS_SYNC_TOKEN for sync-if-due)

import { Hono } from "hono";
import { regionSecret, requireAdmin, requireOps } from "../auth";
import { getAllLeagues, getLeagueRow, pruneOrphanedTeams } from "../db";
import { FootballDataProvider } from "../football";
import { refreshMatchData, refreshStandings } from "../refresh";
import { currentSeasonYear, getSeasonPhase, setSeasonPhase, type SeasonPhase } from "../seasonPhase";
import { runMaintenance, syncTeams } from "../sync";

export const admin = new Hono<{ Bindings: Env }>();

// ── On-demand sync ───────────────────────────────────────────────────────────

admin.post("/sync", async (c) => {
  if (!requireAdmin(c.env, c.req.header("Authorization"))) return c.json({ error: "unauthorized" }, 401);

  const leagueId = c.req.query("league");
  if (!leagueId) return c.json({ error: "league param required" }, 400);

  const league = await getLeagueRow(c.env.DB, leagueId);
  if (!league) return c.json({ error: "league not found in this shard" }, 404);

  const provider = new FootballDataProvider(regionSecret(c.env, "FOOTBALL_DATA_TOKEN"), league.football_data_code, leagueId);
  const seasonParam = c.req.query("season");
  const season = seasonParam ? parseInt(seasonParam, 10) : await currentSeasonYear(c.env.DB, leagueId);

  const what = c.req.query("what") ?? "all";
  const synced: Record<string, number> = {};
  try {
    if (what === "all" || what === "teams") synced.teams = await syncTeams(c.env.DB, provider, season, leagueId);
    if (what === "all" || what === "fixtures" || what === "scores") {
      const m = await refreshMatchData(c.env.DB, c.env.SCORES, provider, season, leagueId);
      synced.fixtures = m.fixtures;
      synced.scores = m.scores;
    }
    if (what === "all" || what === "standings") {
      synced.standings = await refreshStandings(c.env.DB, provider, season, leagueId);
    }
    if (what === "all") await pruneOrphanedTeams(c.env.DB, leagueId);
  } catch (err) {
    return c.json({ ok: false, league: leagueId, season, synced, error: String(err) }, 502);
  }

  return c.json({ ok: true, synced });
});

// Read-only probe — fetches upstream /standings without writing to D1. Use to
// check whether a season's data is published before committing to a real sync.
admin.get("/probe-standings", async (c) => {
  if (!requireAdmin(c.env, c.req.header("Authorization"))) return c.json({ error: "unauthorized" }, 401);

  const leagueId = c.req.query("league");
  if (!leagueId) return c.json({ error: "league param required" }, 400);

  const league = await getLeagueRow(c.env.DB, leagueId);
  if (!league) return c.json({ error: "league not found in this shard" }, 404);

  const seasonParam = c.req.query("season");
  const season = seasonParam ? parseInt(seasonParam, 10) : await currentSeasonYear(c.env.DB, leagueId);
  const provider = new FootballDataProvider(regionSecret(c.env, "FOOTBALL_DATA_TOKEN"), league.football_data_code, leagueId);
  try {
    const standings = await provider.fetchStandings(season);
    return c.json({ ok: true, league: leagueId, season, rowCount: standings.length, rows: standings });
  } catch (err) {
    return c.json({ ok: false, league: leagueId, season, error: String(err) }, 502);
  }
});

// ── Season-phase flag ────────────────────────────────────────────────────────

admin.get("/phase", async (c) => {
  if (!requireAdmin(c.env, c.req.header("Authorization"))) return c.json({ error: "unauthorized" }, 401);
  const leagueId = c.req.query("league");
  if (!leagueId) return c.json({ error: "league param required" }, 400);
  return c.json({ league: leagueId, phase: await getSeasonPhase(c.env.SCORES, leagueId) });
});

admin.post("/phase", async (c) => {
  if (!requireAdmin(c.env, c.req.header("Authorization"))) return c.json({ error: "unauthorized" }, 401);
  const leagueId = c.req.query("league");
  if (!leagueId) return c.json({ error: "league param required" }, 400);
  const value = c.req.query("value");
  if (value !== "live" && value !== "closed") return c.json({ error: "value must be live|closed" }, 400);
  await setSeasonPhase(c.env.SCORES, leagueId, value as SeasonPhase);
  return c.json({ ok: true, league: leagueId, phase: value });
});

// ── Self-gating maintenance trigger ─────────────────────────────────────────
// Called by the orchestrator's shared cron (or the shard's own cron via index.ts
// scheduled handler). Runs maintenance for every league in this shard that
// hasn't already been synced today — idempotent, safe to call multiple times.

admin.post("/sync-if-due", async (c) => {
  if (!requireOps(c.env, c.req.header("Authorization"))) return c.json({ error: "unauthorized" }, 401);

  const now = new Date();
  const currentHour = `${now.getUTCHours().toString().padStart(2, "0")}:00`;
  if (currentHour !== c.env.MAINTENANCE_WINDOW_UTC) return c.json({ ok: true, skipped: "wrong hour" });

  const today = now.toISOString().slice(0, 10);
  const leagues = await getAllLeagues(c.env.DB);
  const results: Record<string, string> = {};

  for (const league of leagues) {
    // Skip if any dataset was synced today — covers both fresh and retry-from-error cases.
    const alreadySynced = await c.env.DB
      .prepare(`SELECT 1 FROM sync_meta WHERE league_id = ? AND synced_at >= ? LIMIT 1`)
      .bind(league.id, today)
      .first();
    if (alreadySynced) { results[league.id] = "skipped"; continue; }

    const provider = new FootballDataProvider(regionSecret(c.env, "FOOTBALL_DATA_TOKEN"), league.football_data_code, league.id);
    try {
      await runMaintenance(c.env.DB, c.env.SCORES, provider, league.id);
      results[league.id] = "done";
    } catch (err) {
      results[league.id] = `error: ${String(err)}`;
    }
  }

  return c.json({ ok: true, leagues: results });
});

// ── League listing ───────────────────────────────────────────────────────────

admin.get("/leagues", async (c) => {
  if (!requireAdmin(c.env, c.req.header("Authorization"))) return c.json({ error: "unauthorized" }, 401);
  const leagues = await getAllLeagues(c.env.DB);
  return c.json({ shard: c.env.SHARD_REGION, leagues });
});
