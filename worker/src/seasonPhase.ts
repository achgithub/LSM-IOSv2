// Per-league season-phase flag, identical in purpose to v1 but with league-scoped
// KV keys so many leagues can share one KV namespace in the v2 shard model.
// Key shape: "{leagueId}:season:phase"
//
// This is a PURE cost/cron switch, nothing more: "live" lets the cron and
// request-triggered gates call upstream as normal; "closed" blocks them
// entirely, regardless of TTL. It carries NO correctness responsibility —
// every upstream call is always pinned to an explicit season (see currentSeasonYear).

export type SeasonPhase = "live" | "closed";

const phaseKey = (leagueId: string) => `${leagueId}:season:phase`;

/** Defaults to "live" when unset — ships inert. */
export async function getSeasonPhase(kv: KVNamespace, leagueId: string): Promise<SeasonPhase> {
  const v = await kv.get(phaseKey(leagueId));
  return v === "closed" ? "closed" : "live";
}

export async function setSeasonPhase(kv: KVNamespace, leagueId: string, phase: SeasonPhase): Promise<void> {
  await kv.put(phaseKey(leagueId), phase);
}

/** A season's name (the year it starts, e.g. 2026 for "2026/27") from a kickoff date. */
function seasonOfDate(d: Date): number {
  const month = d.getUTCMonth() + 1; // 1-12
  return month >= 7 ? d.getUTCFullYear() : d.getUTCFullYear() - 1;
}

/**
 * The season the competition is currently in, derived from D1 fixture data for
 * this league — not football-data.org's own "current season" pointer (which lags).
 * Uses the next upcoming fixture's season; falls back to the latest finished
 * fixture's season if everything is FINISHED (end of season, before next sync).
 */
export async function currentSeasonYear(db: D1Database, leagueId: string): Promise<number> {
  const next = await db
    .prepare(
      `SELECT kickoff FROM fixtures
       WHERE league_id = ? AND status NOT IN ('FINISHED','CANCELLED')
       ORDER BY kickoff ASC LIMIT 1`,
    )
    .bind(leagueId)
    .first<{ kickoff: string }>();
  if (next) return seasonOfDate(new Date(next.kickoff));

  const latest = await db
    .prepare(`SELECT kickoff FROM fixtures WHERE league_id = ? ORDER BY kickoff DESC LIMIT 1`)
    .bind(leagueId)
    .first<{ kickoff: string }>();
  return seasonOfDate(latest ? new Date(latest.kickoff) : new Date());
}
