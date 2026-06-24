// League → shard manifest.
//
// This is the small static map the v2 architecture (docs/lsm-v2-architecture.md
// §2) calls for: before querying anything for a league, the Worker reads this to
// learn which regional shard D1 the league lives in. It changes rarely (only when
// a league is added or a shard is split), so it's a hardcoded manifest rather than
// a table — the manifest decides the binding; the per-shard `leagues` table holds
// the league's detail once you're on the right binding.
//
// Starting topology (Andrew, 2026-06-24): UK + Europe only. More regions
// (North America, South America, …) get added here and as wrangler env blocks.

export type ShardRegion = "uk" | "eu";

/** Every league known to v2, mapped to the shard that holds it. */
export const LEAGUE_SHARD: Record<string, ShardRegion> = {
  // UK shard — PL pulled out on its own region for query volume; ELC rides along.
  PL: "uk",
  ELC: "uk",

  // Europe shard — the rest of the v1 leagues, seeded by copying from their v1 D1s.
  PD: "eu", // La Liga
  BL1: "eu", // Bundesliga
  SA: "eu", // Serie A
  FL1: "eu", // Ligue 1
  DED: "eu", // Eredivisie
};

/** Resolve the shard region for a league id, or undefined if unknown. */
export function shardForLeague(leagueId: string): ShardRegion | undefined {
  return LEAGUE_SHARD[leagueId];
}

/** All distinct shard regions currently in use (for fan-out / admin tooling). */
export function allShards(): ShardRegion[] {
  return [...new Set(Object.values(LEAGUE_SHARD))];
}
