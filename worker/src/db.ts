// D1 access — read queries for the API, write/upsert helpers for the cron sync.
// Only provider-sourced data lives here (teams, fixtures, standings).

import type { Fixture, FixtureStatus, MatchWinner, ScoreEntry, Standing, Team } from "./types";

// ── Row shapes as stored in D1 ──────────────────────────────────────────────
interface TeamRow {
  id: string;
  external_id: number;
  name: string;
  short_name: string | null;
  tla: string | null;
  league_id: string;
}
interface FixtureRow {
  id: number;
  matchday: number | null;
  kickoff: string;
  status: string;
  home_team_id: number;
  away_team_id: number;
  home_score: number | null;
  away_score: number | null;
  winner: string | null;
  updated_at: string;
}
interface StandingRow {
  team_id: number;
  position: number;
  played: number;
  won: number;
  drawn: number;
  lost: number;
  goals_for: number;
  goals_against: number;
  goal_difference: number;
  points: number;
  updated_at: string;
}

function toTeam(r: TeamRow): Team {
  return {
    id: r.id,
    externalId: r.external_id,
    name: r.name,
    shortName: r.short_name,
    tla: r.tla,
    leagueId: r.league_id,
  };
}
function toFixture(r: FixtureRow): Fixture {
  return {
    id: r.id,
    matchday: r.matchday,
    kickoff: r.kickoff,
    status: r.status as FixtureStatus,
    homeTeamId: r.home_team_id,
    awayTeamId: r.away_team_id,
    homeScore: r.home_score,
    awayScore: r.away_score,
    winner: r.winner as MatchWinner,
    updatedAt: r.updated_at,
  };
}
function toStanding(r: StandingRow): Standing {
  return {
    teamId: r.team_id,
    position: r.position,
    played: r.played,
    won: r.won,
    drawn: r.drawn,
    lost: r.lost,
    goalsFor: r.goals_for,
    goalsAgainst: r.goals_against,
    goalDifference: r.goal_difference,
    points: r.points,
    updatedAt: r.updated_at,
  };
}

// ── Reads (API) ─────────────────────────────────────────────────────────────

export interface FixtureQuery {
  dateFrom?: string; // ISO8601 inclusive
  dateTo?: string; // ISO8601 inclusive
  matchday?: number;
}

export async function getFixtures(db: D1Database, q: FixtureQuery = {}): Promise<Fixture[]> {
  const where: string[] = [];
  const binds: unknown[] = [];
  if (q.dateFrom) {
    where.push("kickoff >= ?");
    binds.push(q.dateFrom);
  }
  if (q.dateTo) {
    where.push("kickoff <= ?");
    binds.push(q.dateTo);
  }
  if (q.matchday !== undefined) {
    where.push("matchday = ?");
    binds.push(q.matchday);
  }
  const sql =
    "SELECT * FROM fixtures" +
    (where.length ? ` WHERE ${where.join(" AND ")}` : "") +
    " ORDER BY kickoff ASC";
  const { results } = await db
    .prepare(sql)
    .bind(...binds)
    .all<FixtureRow>();
  return results.map(toFixture);
}

export async function getStandings(db: D1Database): Promise<Standing[]> {
  const { results } = await db
    .prepare("SELECT * FROM standings ORDER BY position ASC")
    .all<StandingRow>();
  return results.map(toStanding);
}

export async function getTeams(db: D1Database): Promise<Team[]> {
  const { results } = await db
    .prepare("SELECT * FROM teams ORDER BY name ASC")
    .all<TeamRow>();
  return results.map(toTeam);
}

// ── v2 league-scoped reads (multi-league shard) ──────────────────────────────
// A v2 shard holds many leagues, so every read is filtered by league_id. These
// serve the app↔DB data path directly off the seeded shard — NO upstream
// provider call (the football-data.org sync is a separate, deferred concern).

/** True if `leagueId` is one of the leagues served by this shard. */
export async function leagueExists(db: D1Database, leagueId: string): Promise<boolean> {
  const row = await db.prepare("SELECT 1 FROM leagues WHERE id = ?").bind(leagueId).first();
  return row !== null;
}

export async function getTeamsByLeague(db: D1Database, leagueId: string): Promise<Team[]> {
  const { results } = await db
    .prepare("SELECT * FROM teams WHERE league_id = ? ORDER BY name ASC")
    .bind(leagueId)
    .all<TeamRow>();
  return results.map(toTeam);
}

export async function getStandingsByLeague(db: D1Database, leagueId: string): Promise<Standing[]> {
  const { results } = await db
    .prepare("SELECT * FROM standings WHERE league_id = ? ORDER BY position ASC")
    .bind(leagueId)
    .all<StandingRow>();
  return results.map(toStanding);
}

export async function getFixturesByLeague(
  db: D1Database,
  leagueId: string,
  q: FixtureQuery = {},
): Promise<Fixture[]> {
  const where = ["league_id = ?"];
  const binds: unknown[] = [leagueId];
  if (q.dateFrom) { where.push("kickoff >= ?"); binds.push(q.dateFrom); }
  if (q.dateTo) { where.push("kickoff <= ?"); binds.push(q.dateTo); }
  if (q.matchday !== undefined) { where.push("matchday = ?"); binds.push(q.matchday); }
  const { results } = await db
    .prepare(`SELECT * FROM fixtures WHERE ${where.join(" AND ")} ORDER BY kickoff ASC`)
    .bind(...binds)
    .all<FixtureRow>();
  return results.map(toFixture);
}

/** Compact live-score view, derived from the fixtures table (no separate live
 *  feed in v2 yet — `minute` is always null until the upstream sync is built). */
export async function getScoresByLeague(db: D1Database, leagueId: string): Promise<ScoreEntry[]> {
  const { results } = await db
    .prepare("SELECT * FROM fixtures WHERE league_id = ? ORDER BY kickoff ASC")
    .bind(leagueId)
    .all<FixtureRow>();
  return results.map((r) => ({
    id: r.id,
    status: r.status as FixtureStatus,
    minute: null,
    homeTeamId: r.home_team_id,
    awayTeamId: r.away_team_id,
    homeScore: r.home_score,
    awayScore: r.away_score,
    winner: r.winner as MatchWinner,
  }));
}

// ── League config (sync) ────────────────────────────────────────────────────

export interface LeagueRow {
  id: string;
  name: string;
  football_data_code: string;
  region: string;
  score_ttl_seconds: number;
  standings_ttl_seconds: number;
  fixtures_ttl_seconds: number;
  status: string;
  maintenance_window_utc: string | null;
}

export async function getLeagueRow(db: D1Database, leagueId: string): Promise<LeagueRow | null> {
  return db
    .prepare(
      `SELECT id, name, football_data_code, region, score_ttl_seconds,
              standings_ttl_seconds, fixtures_ttl_seconds, status, maintenance_window_utc
       FROM leagues WHERE id = ?`,
    )
    .bind(leagueId)
    .first<LeagueRow>();
}

export async function getAllLeagues(db: D1Database): Promise<LeagueRow[]> {
  const { results } = await db
    .prepare(
      `SELECT id, name, football_data_code, region, score_ttl_seconds,
              standings_ttl_seconds, fixtures_ttl_seconds, status, maintenance_window_utc
       FROM leagues ORDER BY id ASC`,
    )
    .all<LeagueRow>();
  return results;
}

// ── Writes (cron sync) ──────────────────────────────────────────────────────

// Upserts the provider's current team list. Pruning teams no longer
// referenced by a fixture or standings row happens separately, in
// pruneOrphanedTeams below — NOT in the same batch as this insert. On a
// brand-new league's very first sync, fixtures/standings are still empty, so
// running the prune here would delete every team this call just inserted
// (nothing references them yet), and the matches sync right after would then
// hit a FK violation on the team rows it expects to still exist.
export async function upsertTeams(db: D1Database, teams: Team[]): Promise<void> {
  if (teams.length === 0) return;
  const stmt = db.prepare(
    `INSERT INTO teams (id, external_id, name, short_name, tla, league_id)
     VALUES (?, ?, ?, ?, ?, ?)
     ON CONFLICT(league_id, external_id) DO UPDATE SET
       name = excluded.name, short_name = excluded.short_name, tla = excluded.tla`,
  );
  await db.batch(teams.map((t) => stmt.bind(t.id, t.externalId, t.name, t.shortName, t.tla, t.leagueId)));
}

// Prunes any team no longer referenced by a fixture or standings row — e.g. a
// team that drops out of the league entirely once `replaceFixtures` +
// `replaceStandings` have cut over to a new season and it's no longer in
// either. Pruning by "not in the latest /teams fetch" instead would risk
// violating the fixtures/standings FK mid-cutover; pruning by "not referenced
// anywhere" is always safe. Call this AFTER fixtures/standings have been
// refreshed in the same maintenance run (see sync.ts runMaintenance), so a
// new league's just-inserted teams are already referenced by the time this runs.
export async function pruneOrphanedTeams(db: D1Database, leagueId: string): Promise<void> {
  await db
    .prepare(
      `DELETE FROM teams WHERE league_id = ? AND external_id NOT IN (
         SELECT home_team_id FROM fixtures WHERE league_id = ?
         UNION SELECT away_team_id FROM fixtures WHERE league_id = ?
         UNION SELECT team_id FROM standings WHERE league_id = ?
       )`,
    )
    .bind(leagueId, leagueId, leagueId, leagueId)
    .run();
}

// Genuinely replaces the table with exactly the fetched rows — same semantics
// as replaceStandings below, and for the same reason: the manager explicitly
// blocks the league, checks the new season is published (read-only probe),
// then runs one deliberate sync to cut over. That sync should leave D1
// holding only the season just fetched, not accumulate old seasons forever —
// the app never lets a user pick a season, so nothing reads historical rows.
// A routine same-season refresh replacing itself with an identical set is a
// harmless no-op; a genuine cutover (different season) is exactly the point.
// DELETE-all-then-insert (not a NOT-IN prune) avoids a 380-row bind-parameter
// list. Guarded on empty input — an empty fetch (transient hiccup, or a
// not-yet-published next season) must never wipe what's already there.
export async function replaceFixtures(db: D1Database, fixtures: Fixture[], leagueId: string): Promise<void> {
  if (fixtures.length === 0) return;
  const del = db.prepare(`DELETE FROM fixtures WHERE league_id = ?`).bind(leagueId);
  const insert = db.prepare(
    `INSERT INTO fixtures
       (id, league_id, matchday, kickoff, status, home_team_id, away_team_id,
        home_score, away_score, winner, updated_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
  );
  await db.batch([
    del,
    ...fixtures.map((f) =>
      insert.bind(
        f.id, leagueId, f.matchday, f.kickoff, f.status, f.homeTeamId, f.awayTeamId,
        f.homeScore, f.awayScore, f.winner, f.updatedAt,
      ),
    ),
  ]);
}

// Genuinely replaces the table with exactly the fetched rows — a team that
// drops out (e.g. relegated, no longer in the new season's table) must stop
// being returned, not linger with its last real points/position forever.
// Nothing has a foreign key into standings.team_id (unlike teams, which
// fixtures/standings reference and so can only prune what's unreferenced —
// see upsertTeams), so a straightforward delete-anything-not-in-this-fetch
// is safe here.
export async function replaceStandings(db: D1Database, standings: Standing[], leagueId: string): Promise<void> {
  if (standings.length === 0) return;
  const insert = db.prepare(
    `INSERT INTO standings
       (league_id, team_id, position, played, won, drawn, lost,
        goals_for, goals_against, goal_difference, points, updated_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
     ON CONFLICT(league_id, team_id) DO UPDATE SET
       position = excluded.position, played = excluded.played,
       won = excluded.won, drawn = excluded.drawn, lost = excluded.lost,
       goals_for = excluded.goals_for, goals_against = excluded.goals_against,
       goal_difference = excluded.goal_difference, points = excluded.points,
       updated_at = excluded.updated_at`,
  );
  const placeholders = standings.map(() => "?").join(",");
  const prune = db.prepare(
    `DELETE FROM standings WHERE league_id = ? AND team_id NOT IN (${placeholders})`,
  );
  await db.batch([
    ...standings.map((s) =>
      insert.bind(
        leagueId, s.teamId, s.position, s.played, s.won, s.drawn, s.lost,
        s.goalsFor, s.goalsAgainst, s.goalDifference, s.points, s.updatedAt,
      ),
    ),
    prune.bind(leagueId, ...standings.map((s) => s.teamId)),
  ]);
}

export async function recordSync(
  db: D1Database,
  leagueId: string,
  dataset: "fixtures" | "standings" | "teams",
  rowCount: number,
): Promise<void> {
  await db
    .prepare(
      `INSERT INTO sync_meta (league_id, dataset, synced_at, row_count)
       VALUES (?, ?, ?, ?)
       ON CONFLICT(league_id, dataset) DO UPDATE SET
         synced_at = excluded.synced_at, row_count = excluded.row_count`,
    )
    .bind(leagueId, dataset, new Date().toISOString(), rowCount)
    .run();
}
