import { Hono } from "hono";
import { requireAdmin } from "../auth";
import { FootballDataProvider } from "../football";
import { refreshMatchData, refreshStandings } from "../refresh";
import { currentSeasonYear, getSeasonPhase, setSeasonPhase, type SeasonPhase } from "../seasonPhase";
import { syncTeams } from "../sync";
import { getLeagueConfig } from "../types";

// Admin endpoint to trigger a provider sync on demand (ops / first seed, or
// pulling in a new season's data immediately instead of waiting for the next
// live cron). Guarded by ADMIN_TOKEN. Independent of the season-phase flag —
// this always runs the real upstream call regardless of live/closed, and
// never touches the phase flag itself; that's a separate, deliberate switch
// (see seasonPhase.ts) the manager controls on its own.
//
//   POST /admin/sync?what=all|teams|fixtures|standings|scores&season=YYYY
//   Authorization: Bearer <ADMIN_TOKEN>
//
// `season` (optional, defaults to currentSeasonYear()) pins the upstream call
// to a specific season instead of football-data.org's own "current
// competition season" pointer — which can lag behind a season that's already
// been published. Override it to deliberately check a different year.
//
// Note: scores + fixtures share one upstream (/matches), so what=fixtures and
// what=scores both run the single combined match refresh (and report both counts).
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
  const seasonParam = c.req.query("season");
  const season = seasonParam ? parseInt(seasonParam, 10) : await currentSeasonYear(c.env.DB);

  const what = c.req.query("what") ?? "all";
  const synced: Record<string, number> = {};
  // Teams first (fixtures + standings reference them).
  if (what === "all" || what === "teams") synced.teams = await syncTeams(c.env.DB, provider, season);
  if (what === "all" || what === "fixtures" || what === "scores") {
    const m = await refreshMatchData(c.env.DB, c.env.SCORES, provider, season);
    synced.fixtures = m.fixtures;
    synced.scores = m.scores;
  }
  if (what === "all" || what === "standings") {
    synced.standings = await refreshStandings(c.env.DB, provider, season);
  }

  return c.json({ ok: true, synced });
});

// Read-only diagnostic: calls the upstream /standings endpoint for a given
// season WITHOUT writing anything to D1 — for checking whether a not-yet-
// started season returns an empty table or still falls back to a previous
// one, before deciding to run a real (destructive, replaces D1) sync.
//
//   GET /admin/probe-standings?season=YYYY   (season optional, defaults to currentSeasonYear())
//   Authorization: Bearer <ADMIN_TOKEN>
admin.get("/probe-standings", async (c) => {
  if (!requireAdmin(c.env, c.req.header("Authorization"))) {
    return c.json({ error: "unauthorized" }, 401);
  }
  const seasonParam = c.req.query("season");
  const season = seasonParam ? parseInt(seasonParam, 10) : await currentSeasonYear(c.env.DB);
  const cfg = getLeagueConfig(c.env);
  const provider = new FootballDataProvider(
    c.env.FOOTBALL_DATA_TOKEN,
    cfg.footballDataCode,
    cfg.leagueId,
  );
  try {
    const standings = await provider.fetchStandings(season);
    return c.json({ ok: true, season, rowCount: standings.length, rows: standings });
  } catch (err) {
    return c.json({ ok: false, season, error: String(err) }, 502);
  }
});

// Season-phase flag (live | closed — see seasonPhase.ts). A PURE cost switch:
// "closed" blocks the cron and all request-triggered upstream calls entirely;
// it has no bearing on correctness, since every upstream call (through this
// gate or /admin/sync above) is always pinned to an explicit season. Curl
// fallback for the dashboard's buttons (worker-dash writes the same KV key
// directly, since it's already bound there); kept here too so this is
// controllable without dashboard access, and documented in one place.
//
//   GET  /admin/phase
//   POST /admin/phase?value=live|closed
//   Authorization: Bearer <ADMIN_TOKEN>
admin.get("/phase", async (c) => {
  if (!requireAdmin(c.env, c.req.header("Authorization"))) {
    return c.json({ error: "unauthorized" }, 401);
  }
  return c.json({ phase: await getSeasonPhase(c.env.SCORES) });
});

admin.post("/phase", async (c) => {
  if (!requireAdmin(c.env, c.req.header("Authorization"))) {
    return c.json({ error: "unauthorized" }, 401);
  }
  const value = c.req.query("value");
  if (value !== "live" && value !== "closed") {
    return c.json({ error: "value must be live|closed" }, 400);
  }
  await setSeasonPhase(c.env.SCORES, value as SeasonPhase);
  return c.json({ ok: true, phase: value });
});
