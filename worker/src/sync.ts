// Nightly maintenance + on-demand seeding — v2 edition.
// Mechanically identical to v1: teams sync first, then matches+standings, then
// prune. Gate resets at the end so the first user of the day gets fresh data.
// Only v2 difference: leagueId param scopes all DB writes and KV keys.

import { pruneOrphanedTeams, recordSync, upsertTeams } from "./db";
import type { Provider } from "./football";
import { leagueKeys, resetGate } from "./gate";
import { refreshMatchData, refreshStandings } from "./refresh";
import { currentSeasonYear, getSeasonPhase } from "./seasonPhase";

export async function syncTeams(
  db: D1Database,
  provider: Provider,
  season: number,
  leagueId: string,
): Promise<number> {
  const teams = await provider.fetchTeams(season);
  if (teams.length === 0) return 0;
  await upsertTeams(db, teams);
  await recordSync(db, leagueId, "teams", teams.length);
  return teams.length;
}

// Full nightly maintenance for one league. Called by POST /admin/sync-if-due
// (orchestrator-driven) or directly from the shard's cron scheduled handler.
// Order: teams → matches+standings → prune → gate reset.
export async function runMaintenance(
  db: D1Database,
  kv: KVNamespace,
  provider: Provider,
  leagueId: string,
): Promise<void> {
  if ((await getSeasonPhase(kv, leagueId)) !== "live") {
    console.log(JSON.stringify({ msg: "maintenance skipped — season closed", leagueId }));
    return;
  }

  const season = await currentSeasonYear(db, leagueId);
  const teams = await syncTeams(db, provider, season, leagueId);
  const { scores, fixtures } = await refreshMatchData(db, kv, provider, season, leagueId);
  const standings = await refreshStandings(db, provider, season, leagueId);
  await pruneOrphanedTeams(db, leagueId);

  // Reset all gates to a clean (0,0)+now state — first user of the day gets
  // fresh data without triggering another upstream call.
  const keys = leagueKeys(leagueId);
  await Promise.all([
    resetGate(kv, keys.scores),
    resetGate(kv, keys.fixtures),
    resetGate(kv, keys.standings),
  ]);

  console.log(JSON.stringify({ msg: "maintenance done", leagueId, season, teams, fixtures, standings, scores }));
}
