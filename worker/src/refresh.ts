// Upstream → store refreshers. Identical semantics to v1 (one /matches fetch
// warms both scores KV blob + fixtures D1, co-warms the sibling gate). The only
// v2 difference: all writes and KV keys are scoped by leagueId so many leagues
// can share one D1 and one KV namespace in a regional shard.

import { recordSync, replaceFixtures, replaceStandings } from "./db";
import type { Provider } from "./football";
import { leagueKeys, touchGate } from "./gate";

export interface MatchCounts {
  scores: number;
  fixtures: number;
}

/**
 * Fetch /matches once → cache compact scores in KV, store full fixtures in D1,
 * co-warm both gates. Identical to v1's refreshMatchData except all keys and
 * DB writes are league-scoped.
 */
export async function refreshMatchData(
  db: D1Database,
  kv: KVNamespace,
  provider: Provider,
  season: number,
  leagueId: string,
): Promise<MatchCounts> {
  const { scores, fixtures } = await provider.fetchMatchData(season);
  if (fixtures.length === 0) return { scores: 0, fixtures: 0 };
  const keys = leagueKeys(leagueId);
  await replaceFixtures(db, fixtures, leagueId);
  await recordSync(db, leagueId, "fixtures", fixtures.length);
  await kv.put(keys.scoresData, JSON.stringify(scores));
  await Promise.all([touchGate(kv, keys.scores), touchGate(kv, keys.fixtures)]);
  return { scores: scores.length, fixtures: fixtures.length };
}

/**
 * Fetch /standings → replace in D1. No KV data key (standings are served
 * straight from D1). Gate settlement is handled by withFreshness in gate.ts.
 */
export async function refreshStandings(
  db: D1Database,
  provider: Provider,
  season: number,
  leagueId: string,
): Promise<number> {
  const standings = await provider.fetchStandings(season);
  if (standings.length === 0) return 0;
  await replaceStandings(db, standings, leagueId);
  await recordSync(db, leagueId, "standings", standings.length);
  return standings.length;
}
