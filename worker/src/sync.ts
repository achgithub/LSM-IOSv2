// Nightly maintenance + on-demand seeding (spec §10.3).
// Teams have no request-triggered gate (they change at most seasonally), so the
// cron is their only refresh path. Matches (scores+fixtures) and standings DO
// have request-triggered gates (see refresh.ts / the routes) which cover the
// rest of the day; the cron's extra job for them is to warm the stores and reset
// the gates to a clean (0,0) state for the day's first user.

import { pruneOrphanedTeams, recordSync, upsertTeams } from "./db";
import type { Provider } from "./football";
import { FIXTURES_KEYS, resetGate, SCORES_KEYS, STANDINGS_KEYS } from "./gate";
import { refreshMatchData, refreshStandings } from "./refresh";
import { currentSeasonYear, getSeasonPhase } from "./seasonPhase";

export async function syncTeams(db: D1Database, provider: Provider, season: number): Promise<number> {
  const teams = await provider.fetchTeams(season);
  if (teams.length === 0) return 0;
  await upsertTeams(db, teams);
  await recordSync(db, "teams", teams.length);
  return teams.length;
}

// Full nightly maintenance, triggered once a day by POST /admin/sync-if-due
// (see routes/admin.ts) when worker-registry's single shared orchestrator cron
// pings this league during its own MAINTENANCE_WINDOW_UTC hour. Order: teams
// first (fixtures + standings reference them), then matches and standings.
// All of this runs in the league's maintenance window (the dead zone), so the
// serial upstream calls are free of contention and well within the rate limit.
export async function runMaintenance(
  db: D1Database,
  kv: KVNamespace,
  provider: Provider,
): Promise<void> {
  // Outside "live" (closed — see seasonPhase.ts), there is nothing worth
  // spending the call on: a manager has deliberately frozen the close-season
  // cache. Skip entirely; don't even reset the gates (nothing was refreshed
  // for them to be settled against).
  if ((await getSeasonPhase(kv)) !== "live") {
    console.log(JSON.stringify({ msg: "cron skipped — season phase not live" }));
    return;
  }

  // Always pinned to the current football season (see currentSeasonYear) —
  // never the provider's own ambiguous "current competition season" pointer,
  // which can still lag behind a season that's already been published.
  const season = await currentSeasonYear(db);
  const teams = await syncTeams(db, provider, season);
  const { scores, fixtures } = await refreshMatchData(db, kv, provider, season);
  const standings = await refreshStandings(db, provider, season);
  // Prune AFTER fixtures/standings, not as part of syncTeams — otherwise a
  // brand-new league's just-inserted teams (unreferenced by anything yet)
  // would be deleted before the fixtures insert that needs them. See
  // db.ts pruneOrphanedTeams.
  await pruneOrphanedTeams(db);
  // Reset every gate to a settled (0,0)+now state: fresh for the day's first
  // user, no accumulated integer drift. This overrides the touch refreshMatchData
  // just applied — intentional; the nightly window is the clean-slate point.
  await Promise.all([
    resetGate(kv, SCORES_KEYS),
    resetGate(kv, FIXTURES_KEYS),
    resetGate(kv, STANDINGS_KEYS),
  ]);
  console.log(
    JSON.stringify({ msg: "cron maintenance", teams, fixtures, standings, scores }),
  );
}
