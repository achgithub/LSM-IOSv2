import { LEAGUE_SHARD, type ShardRegion } from "./shards";

// The league-discovery manifest, served at GET /leagues.json in the SAME shape
// the app bundles as `leagues.json` (app / homeLeagueId / leagues[]). The app's
// `Leagues.refreshFromRegistry` points at this so it discovers v2 leagues + their
// shard URLs — replacing v1's registry worker (deleted in the v2 separation).
//
// Both shard workers serve the identical full manifest, so the app gets every
// league from whichever one it asks.

// Public base URL of each shard worker (workers.dev). Filled in after the first
// deploy prints the URLs — see worker/MIGRATION.md.
export const SHARD_BASE: Record<ShardRegion, string> = {
  uk: "https://lsm-uk-worker.sportsmanager.workers.dev",
  eu: "https://lsm-eu-worker.sportsmanager.workers.dev",
};

interface LeagueMeta {
  name: string; // "Country — League" (the app strips the prefix for chips)
  shortName: string;
  teamsCount: number;
}

// Every league v2 serves, with display metadata. Region comes from shards.ts.
const LEAGUES: Record<string, LeagueMeta> = {
  PL: { name: "England — Premier League", shortName: "PL", teamsCount: 20 },
  ELC: { name: "England — Championship", shortName: "ELC", teamsCount: 24 },
  PD: { name: "España — La Liga", shortName: "PD", teamsCount: 20 },
  BL1: { name: "Deutschland — Bundesliga", shortName: "BL1", teamsCount: 18 },
  SA: { name: "Italia — Serie A", shortName: "SA", teamsCount: 20 },
  FL1: { name: "France — Ligue 1", shortName: "FL1", teamsCount: 18 },
  DED: { name: "Nederland — Eredivisie", shortName: "DED", teamsCount: 18 },
};

/** Build the app-shaped manifest. Each league's workerBaseURL points at its
 *  shard's `/leagues/<id>` base, so the app's APIClient appends `/fixtures` etc. */
export function buildManifest() {
  const leagues = Object.entries(LEAGUES).map(([id, m]) => ({
    id,
    name: m.name,
    shortName: m.shortName,
    workerBaseURL: `${SHARD_BASE[LEAGUE_SHARD[id]]}/leagues/${id}`,
    teamsCount: m.teamsCount,
  }));
  return {
    app: { name: "Last Stand Manager", season: "2025/26", allowRepeatDefault: false },
    homeLeagueId: "PL",
    leagues,
  };
}
