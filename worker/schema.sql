-- LSM v2 Worker — D1 schema (REGIONAL SHARD instance, e.g. lsm-uk-db, lsm-eu-db)
--
-- Scope change from v1: v1 ran one D1 *per league* (lms-pl-db, lms-elc-db, …),
-- each scoped to a single league with a static league.config.json baked into the
-- bundle, and it stored ONLY upstream sports data — all game state lived on the
-- device. v2 instead runs a small fixed number of REGIONAL SHARD databases, each
-- holding MANY leagues, and is the source of truth for game state too (cloud-backed
-- from day one so Predictor's season-long state survives a phone change).
--
-- Two layers live in every shard:
--   1. Shared sports data  — leagues / teams / fixtures / standings (+ sync_meta).
--      These rows are keyed by league_id so one shard serves many leagues.
--   2. Per-game/per-player  — games / players / picks / predictions /
--      submission_tokens / submissions. This is the layer v1 never had.
--
-- Provider ids (football-data.org) are globally unique across leagues
-- (teams.external_id, fixtures.id), so co-locating leagues in one shard needs
-- no id renumbering.
--
-- Apply: wrangler d1 execute lsm-uk-db --env uk --remote --file=./schema.sql
--        wrangler d1 execute lsm-eu-db --env eu --remote --file=./schema.sql

PRAGMA foreign_keys = ON;

-- ════════════════════════════════════════════════════════════════════════════
--  LAYER 1 — shared sports data (replaces per-league D1 + league.config.json)
-- ════════════════════════════════════════════════════════════════════════════

-- ── Leagues ──────────────────────────────────────────────────────────────────
-- One row per league served by THIS shard. Replaces v1's static
-- league.config.json files — the config is now rows, not files. A separate
-- static league→shard manifest (src/shards.ts) decides which shard a league_id
-- lives in; this table is the per-shard detail once you're on the right binding.
CREATE TABLE IF NOT EXISTS leagues (
  id                  TEXT PRIMARY KEY,          -- LEAGUE_ID, e.g. "PL", "ELC", "PD"
  name                TEXT NOT NULL,             -- "Premier League"
  football_data_code  TEXT NOT NULL,             -- provider competition code, e.g. "PL"
  region              TEXT NOT NULL,             -- shard region key, e.g. "uk" | "eu"
  teams_count         INTEGER NOT NULL,
  rounds_per_season   INTEGER NOT NULL,
  timezone            TEXT NOT NULL,             -- IANA tz, e.g. "Europe/London"
  -- Per-resource upstream TTLs (Layer 2 cost control), carried over from v1 vars.
  score_ttl_seconds      INTEGER NOT NULL DEFAULT 120,
  standings_ttl_seconds  INTEGER NOT NULL DEFAULT 1800,
  fixtures_ttl_seconds   INTEGER NOT NULL DEFAULT 14400,
  maintenance_window_utc TEXT,                   -- "HH:MM", quiet hour for migrations
  status              TEXT NOT NULL DEFAULT 'live', -- live | closed | rollover (season-phase)
  created_at          TEXT NOT NULL,
  updated_at          TEXT NOT NULL
);

-- ── Teams ────────────────────────────────────────────────────────────────────
-- One row per (league, club). `external_id` is the provider's team id — globally
-- unique as an *identifier*, but the SAME club can be a member of two leagues
-- co-located in one shard (a club relegated PL→ELC appears in both, e.g. PL on
-- 2026 data + ELC on 2025 data). So the key is COMPOSITE (league_id, external_id),
-- NOT external_id alone — otherwise those clubs collide and one league loses rows.
-- Only text data is stored — the app renders bespoke colour tiles, so the
-- provider's crest/logo image URL is deliberately NOT persisted or served.
CREATE TABLE IF NOT EXISTS teams (
  external_id INTEGER NOT NULL,           -- football-data.org team id (repeats across leagues)
  league_id   TEXT NOT NULL REFERENCES leagues (id),
  id          TEXT NOT NULL,              -- provider id as text (mirror of external_id); not unique across leagues
  name        TEXT NOT NULL,
  short_name  TEXT,                       -- e.g. "Arsenal"
  tla         TEXT,                       -- provider 3-letter code, e.g. "ARS"
  PRIMARY KEY (league_id, external_id)
);

CREATE INDEX IF NOT EXISTS idx_teams_external ON teams (external_id);
CREATE INDEX IF NOT EXISTS idx_teams_league   ON teams (league_id);

-- ── Fixtures ─────────────────────────────────────────────────────────────────
-- Live/recent fixtures synced from the provider. `id` is the provider match id.
-- v2 adds league_id so one shard can hold fixtures for several leagues.
CREATE TABLE IF NOT EXISTS fixtures (
  id           INTEGER PRIMARY KEY,        -- football-data.org match id
  league_id    TEXT NOT NULL REFERENCES leagues (id),
  matchday     INTEGER,                    -- league matchday / round number
  kickoff      TEXT NOT NULL,              -- ISO8601, always UTC
  status       TEXT NOT NULL,              -- SCHEDULED | TIMED | IN_PLAY | PAUSED | FINISHED | POSTPONED | SUSPENDED | CANCELLED
  home_team_id INTEGER NOT NULL,
  away_team_id INTEGER NOT NULL,
  home_score   INTEGER,                    -- null until played
  away_score   INTEGER,                    -- null until played
  winner       TEXT,                       -- HOME_TEAM | AWAY_TEAM | DRAW | null
  updated_at   TEXT NOT NULL,              -- ISO8601 UTC, last sync write
  -- Composite FKs: a team is identified within its league (see teams' composite PK).
  FOREIGN KEY (league_id, home_team_id) REFERENCES teams (league_id, external_id),
  FOREIGN KEY (league_id, away_team_id) REFERENCES teams (league_id, external_id)
);

CREATE INDEX IF NOT EXISTS idx_fixtures_league   ON fixtures (league_id);
CREATE INDEX IF NOT EXISTS idx_fixtures_kickoff  ON fixtures (kickoff);
CREATE INDEX IF NOT EXISTS idx_fixtures_matchday ON fixtures (league_id, matchday);
CREATE INDEX IF NOT EXISTS idx_fixtures_status   ON fixtures (status);

-- ── Standings ────────────────────────────────────────────────────────────────
-- League table, one row per (league, team). The PK is COMPOSITE (league_id,
-- team_id) for the same reason as teams: a club in two co-located leagues must
-- hold a standings row in each. Keying on team_id alone silently drops the
-- duplicate (e.g. PL would lose its 3 relegated/promoted clubs to ELC).
CREATE TABLE IF NOT EXISTS standings (
  league_id  TEXT NOT NULL REFERENCES leagues (id),
  team_id    INTEGER NOT NULL,             -- provider team id
  position   INTEGER NOT NULL,
  played     INTEGER NOT NULL DEFAULT 0,
  won        INTEGER NOT NULL DEFAULT 0,
  drawn      INTEGER NOT NULL DEFAULT 0,
  lost       INTEGER NOT NULL DEFAULT 0,
  goals_for     INTEGER NOT NULL DEFAULT 0,
  goals_against INTEGER NOT NULL DEFAULT 0,
  goal_difference INTEGER NOT NULL DEFAULT 0,
  points     INTEGER NOT NULL DEFAULT 0,
  updated_at TEXT NOT NULL,                -- ISO8601 UTC
  PRIMARY KEY (league_id, team_id),
  FOREIGN KEY (league_id, team_id) REFERENCES teams (league_id, external_id)
);

CREATE INDEX IF NOT EXISTS idx_standings_league   ON standings (league_id, position);

-- ── Sync metadata ────────────────────────────────────────────────────────────
-- Last successful upstream sync per (league, dataset), for observability and
-- freshness reporting. v2 keys by league_id since one shard syncs many leagues.
CREATE TABLE IF NOT EXISTS sync_meta (
  league_id  TEXT NOT NULL REFERENCES leagues (id),
  dataset    TEXT NOT NULL,                -- 'fixtures' | 'standings' | 'teams'
  synced_at  TEXT NOT NULL,               -- ISO8601 UTC
  row_count  INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (league_id, dataset)
);

-- ── App Attest devices ───────────────────────────────────────────────────────
-- One row per attested app instance (hardware-backed key on a real device).
-- Shared across leagues within the shard. Unchanged in shape from v1.
CREATE TABLE IF NOT EXISTS attest_devices (
  key_id      TEXT PRIMARY KEY,            -- base64 keyId = SHA256(public key)
  public_key  TEXT NOT NULL,              -- base64 raw (uncompressed P-256) public key
  sign_count  INTEGER NOT NULL DEFAULT 0, -- last accepted assertion counter
  environment TEXT NOT NULL,              -- 'production' | 'development' (AAGUID)
  created_at  TEXT NOT NULL,              -- ISO8601 UTC, attestation accepted
  updated_at  TEXT NOT NULL               -- ISO8601 UTC, last assertion accepted
);

-- ════════════════════════════════════════════════════════════════════════════
--  LAYER 2 — per-game / per-player state (NEW in v2; v1 kept this on-device)
-- ════════════════════════════════════════════════════════════════════════════

-- ── Games ────────────────────────────────────────────────────────────────────
-- One row per game a manager runs. `mode` is the discriminator between the two
-- modes that share this engine. `settings` is a JSON blob whose meaningful keys
-- differ by mode (LMS: allowRepeats, drawEliminates; Predictor: scoring rules).
CREATE TABLE IF NOT EXISTS games (
  id          TEXT PRIMARY KEY,            -- uuid
  mode        TEXT NOT NULL,               -- 'lms' | 'predictor'
  league_id   TEXT NOT NULL REFERENCES leagues (id),
  name        TEXT NOT NULL,
  settings    TEXT NOT NULL DEFAULT '{}',  -- JSON: mode-specific rules
  status      TEXT NOT NULL DEFAULT 'active', -- active | finished | archived
  created_at  TEXT NOT NULL,
  updated_at  TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_games_league ON games (league_id);

-- ── Players ──────────────────────────────────────────────────────────────────
-- One row per participant in a game. `status` is meaningful for LMS (active vs
-- eliminated); for Predictor everyone stays 'active' (no elimination — they can
-- join/leave mid-season).
CREATE TABLE IF NOT EXISTS players (
  id           TEXT PRIMARY KEY,           -- uuid
  game_id      TEXT NOT NULL REFERENCES games (id) ON DELETE CASCADE,
  display_name TEXT NOT NULL,
  status       TEXT NOT NULL DEFAULT 'active', -- active | eliminated (LMS only)
  joined_at    TEXT NOT NULL,
  left_at      TEXT
);

CREATE INDEX IF NOT EXISTS idx_players_game ON players (game_id);

-- ── Picks (LMS) ──────────────────────────────────────────────────────────────
-- One pick per player per round. `result` is filled once the round resolves.
CREATE TABLE IF NOT EXISTS picks (
  id          TEXT PRIMARY KEY,            -- uuid
  player_id   TEXT NOT NULL REFERENCES players (id) ON DELETE CASCADE,
  round_id    INTEGER NOT NULL,            -- matchday number within the game's league
  team_id     INTEGER NOT NULL,            -- provider team id; league is implied by the game (no
                                           -- DB-level FK: teams is keyed (league_id, external_id),
                                           -- and picks doesn't carry league_id — app-enforced)
  result      TEXT,                        -- win | loss | draw | pending
  created_at  TEXT NOT NULL,
  UNIQUE (player_id, round_id)
);

CREATE INDEX IF NOT EXISTS idx_picks_player ON picks (player_id);
CREATE INDEX IF NOT EXISTS idx_picks_round  ON picks (round_id);

-- ── Predictions (Predictor) ──────────────────────────────────────────────────
-- One prediction per player per fixture. `points_awarded` is computed once the
-- fixture finishes, against the game's scoring rules (games.settings).
CREATE TABLE IF NOT EXISTS predictions (
  id                    TEXT PRIMARY KEY,  -- uuid
  player_id             TEXT NOT NULL REFERENCES players (id) ON DELETE CASCADE,
  fixture_id            INTEGER NOT NULL REFERENCES fixtures (id),
  predicted_home_score  INTEGER NOT NULL,
  predicted_away_score  INTEGER NOT NULL,
  points_awarded        INTEGER,           -- null until the fixture finishes & is scored
  created_at            TEXT NOT NULL,
  UNIQUE (player_id, fixture_id)
);

CREATE INDEX IF NOT EXISTS idx_predictions_player  ON predictions (player_id);
CREATE INDEX IF NOT EXISTS idx_predictions_fixture ON predictions (fixture_id);

-- ── Submission tokens ────────────────────────────────────────────────────────
-- The per-player unguessable PWA link. No email / no account (deliberately out
-- of GDPR personal-data scope). One active token per player; revoking sets
-- revoked_at rather than deleting (keeps an audit trail of issued links).
CREATE TABLE IF NOT EXISTS submission_tokens (
  id          TEXT PRIMARY KEY,            -- uuid (internal)
  player_id   TEXT NOT NULL REFERENCES players (id) ON DELETE CASCADE,
  token       TEXT NOT NULL UNIQUE,        -- the UUID that appears in the player's link
  created_at  TEXT NOT NULL,
  revoked_at  TEXT
);

CREATE INDEX IF NOT EXISTS idx_tokens_player ON submission_tokens (player_id);

-- ── Submissions (the approval queue) ─────────────────────────────────────────
-- A player's self-submitted pick/prediction lands here as 'pending' — it does
-- NOT write straight into picks/predictions. The manager approves (which creates
-- the real pick/prediction row) or rejects. Manager-typed entries skip this
-- table entirely and write straight through.
CREATE TABLE IF NOT EXISTS submissions (
  id           TEXT PRIMARY KEY,           -- uuid
  token_id     TEXT NOT NULL REFERENCES submission_tokens (id) ON DELETE CASCADE,
  game_id      TEXT NOT NULL REFERENCES games (id) ON DELETE CASCADE,
  context      TEXT NOT NULL,              -- JSON: { round_id } (LMS) or { fixture_id } (Predictor)
  payload      TEXT NOT NULL,              -- JSON: { team_id } or { home, away }
  status       TEXT NOT NULL DEFAULT 'pending', -- pending | approved | rejected
  submitted_at TEXT NOT NULL,
  decided_at   TEXT
);

CREATE INDEX IF NOT EXISTS idx_submissions_game   ON submissions (game_id, status);
CREATE INDEX IF NOT EXISTS idx_submissions_token  ON submissions (token_id);
