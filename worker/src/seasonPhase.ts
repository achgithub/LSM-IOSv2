// Per-league cache-only flag for the close season, distinct from the
// deploy-outage "maintenance mode" concept — see lms-season-phase-rollover
// memory. Stored as a single KV string per league Worker, so no cross-league
// coordination is needed (each league has its own KV namespace).
//
// This is a PURE cost/cron switch, nothing more: "live" lets the cron and
// request-triggered gates call upstream as normal; "closed" blocks them
// entirely, regardless of TTL, so polling a competition that has nothing new
// to say doesn't burn API quota. It carries NO correctness responsibility —
// every upstream call (whether through this gate or the on-demand admin
// sync) is always pinned to an explicit season (see currentSeasonYear
// below), so fixtures/teams/standings can never disagree about which season
// they're describing, whatever this flag is set to.

export type SeasonPhase = "live" | "closed";

const PHASE_KEY = "season:phase";

/** Defaults to "live" (today's behaviour) when unset — ships inert. */
export async function getSeasonPhase(kv: KVNamespace): Promise<SeasonPhase> {
  const v = await kv.get(PHASE_KEY);
  return v === "closed" ? v : "live";
}

export async function setSeasonPhase(kv: KVNamespace, phase: SeasonPhase): Promise<void> {
  await kv.put(PHASE_KEY, phase);
}

/** A season's name (the year it starts, e.g. 2026 for "2026/27") from a kickoff date. */
function seasonOfDate(d: Date): number {
  const month = d.getUTCMonth() + 1; // 1-12
  return month >= 7 ? d.getUTCFullYear() : d.getUTCFullYear() - 1;
}

/**
 * The season a competition should currently be treated as being in,
 * independent of whatever football-data.org itself currently calls "current"
 * for that competition — that pointer lags reality (e.g. it can still point
 * at last season weeks after next season's fixtures are published).
 *
 * Derived from D1's own fixture data rather than the wall clock: a fixed
 * calendar cutover (e.g. "July onward = next season") can't track real
 * season-end dates, which shift year to year — a season finishing in May
 * means the *next* season is already the right default for the whole of
 * June, not just from July. So: use whichever season the next NOT-YET-
 * FINISHED fixture belongs to (the season "in progress or about to start"),
 * falling back to the most recent fixture's season if everything on file is
 * finished (e.g. right after a season ends, before next season's fixtures
 * have even been synced yet — nothing better to default to).
 */
export async function currentSeasonYear(db: D1Database): Promise<number> {
  const next = await db
    .prepare(
      `SELECT kickoff FROM fixtures WHERE status NOT IN ('FINISHED','CANCELLED')
       ORDER BY kickoff ASC LIMIT 1`,
    )
    .first<{ kickoff: string }>();
  if (next) return seasonOfDate(new Date(next.kickoff));

  const latest = await db
    .prepare(`SELECT kickoff FROM fixtures ORDER BY kickoff DESC LIMIT 1`)
    .first<{ kickoff: string }>();
  return seasonOfDate(latest ? new Date(latest.kickoff) : new Date());
}
