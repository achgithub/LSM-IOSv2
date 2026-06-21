// Upstream → store refreshers, shared by the request-triggered gates (routes),
// the on-demand admin sync, and the nightly cron. Each fetches the provider once
// and writes the relevant store(s); the gate counters are managed by gate.ts.

import { recordSync, replaceFixtures, replaceStandings } from "./db";
import type { Provider } from "./football";
import { FIXTURES_KEYS, SCORES_DATA_KEY, SCORES_KEYS, touchGate } from "./gate";

export interface MatchCounts {
  scores: number;
  fixtures: number;
}

/**
 * Fetch /matches once → cache the compact scores in KV, store the full fixtures
 * in D1, then mark BOTH the scores and fixtures gates fresh. Scores and fixtures
 * share this one upstream source, so a scores refresh co-warms fixtures and a
 * fixtures refresh co-warms scores ("one /matches → both timestamps", spec
 * cross-resource warming). The caller's own gate is settled by gate.ts on top of
 * this — the touch here is what keeps the *sibling* gate from re-fetching.
 *
 * Both D1 (replaceFixtures) and the KV scores blob are full replacements of
 * whatever `season` resolves to — never an accumulation across seasons. A
 * routine same-season refresh replaces itself (a no-op in effect); a
 * deliberate manager-triggered cutover to a new season correctly drops the
 * old one from both stores in the same call.
 *
 * An EMPTY fetch (e.g. a season probed/synced before its fixtures are
 * actually published upstream) must change nothing in either store — same
 * guard `replaceFixtures` already has on the D1 side, applied here to the KV
 * scores blob too (it has no guard of its own; an empty `scores` array would
 * otherwise silently replace real cached data with `[]`). `recordSync` only
 * fires when something genuinely changed, so sync_meta/health never reports
 * a misleading "0 rows" for a write that was correctly skipped.
 */
export async function refreshMatchData(
  db: D1Database,
  kv: KVNamespace,
  provider: Provider,
  season: number,
): Promise<MatchCounts> {
  const { scores, fixtures } = await provider.fetchMatchData(season);
  if (fixtures.length === 0) {
    return { scores: 0, fixtures: 0 };
  }
  await replaceFixtures(db, fixtures);
  await recordSync(db, "fixtures", fixtures.length);
  await kv.put(SCORES_DATA_KEY, JSON.stringify(scores));
  await Promise.all([touchGate(kv, SCORES_KEYS), touchGate(kv, FIXTURES_KEYS)]);
  return { scores: scores.length, fixtures: fixtures.length };
}

/**
 * Fetch the league table → replace it in D1. Standings have their own upstream
 * (/standings) and their own gate; nothing co-warms them. Same empty-fetch
 * guard as refreshMatchData — recordSync only fires on a genuine write.
 */
export async function refreshStandings(db: D1Database, provider: Provider, season: number): Promise<number> {
  const standings = await provider.fetchStandings(season);
  if (standings.length === 0) return 0;
  await replaceStandings(db, standings);
  await recordSync(db, "standings", standings.length);
  return standings.length;
}
