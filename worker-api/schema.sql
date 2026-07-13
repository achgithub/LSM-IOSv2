-- LSM API Authority — D1 schema
-- One instance per regional authority (lsm-api-uk-db, lsm-api-eu-db, …).
--
-- This database owns everything that is NOT sports data:
--   • App Attest device registry (one row per enrolled device)
--   • PWA submission queue (player_tokens, game_enrollments, round_pushes, submissions)
--   • Cloud backup metadata (manager_lifecycle, manager_backups)
--   • Publish links
--
-- Sports data (leagues, teams, fixtures, standings) stays in the sports shard DBs.
--
-- Apply (fresh databases only — CREATE TABLE IF NOT EXISTS is a no-op against
-- an existing table, so this alone does not add new columns to uk/eu):
--   pnpm db:migrate:uk   (or db:migrate:eu)
--
-- One-off column additions to existing tables live in migrations/*.sql —
-- apply those manually, once per region, before deploying code that depends
-- on them. See migrations/0001_add_round_pushes_extra_json.sql.

PRAGMA foreign_keys = ON;

-- ── App Attest devices ────────────────────────────────────────────────────────
-- One row per enrolled device. Registration happens once (per device per authority);
-- assertions are verified on every /attest/assert call and the sign counter advances.
CREATE TABLE IF NOT EXISTS attest_devices (
  key_id      TEXT PRIMARY KEY,
  public_key  TEXT NOT NULL,              -- base64 raw uncompressed P-256 point
  sign_count  INTEGER NOT NULL DEFAULT 0,
  environment TEXT NOT NULL,              -- 'production' | 'development'
  manager_token TEXT,                     -- links this device to its owning manager, for cascade delete
  created_at  TEXT NOT NULL,
  updated_at  TEXT NOT NULL
);

-- ── Player tokens ─────────────────────────────────────────────────────────────
-- One unguessable token per player in the manager's roster.
-- One link works across all games (game-level scoping is in game_enrollments).
CREATE TABLE IF NOT EXISTS player_tokens (
  token        TEXT PRIMARY KEY,
  player_name  TEXT NOT NULL,
  manager_token TEXT,                     -- links this player to the owning manager
  manager_name  TEXT,                     -- display name for the PWA "Manager: X" line
  created_at   TEXT NOT NULL,
  revoked_at   TEXT,
  last_used_at TEXT                       -- bumped on GET /s/:token (player or manager viewing-as-player)
);

CREATE INDEX IF NOT EXISTS idx_player_tokens_manager ON player_tokens (manager_token);

-- ── Game enrollments ─────────────────────────────────────────────────────────
-- Per-(player, game) enrollment. Refreshed on every round push.
CREATE TABLE IF NOT EXISTS game_enrollments (
  token                  TEXT NOT NULL REFERENCES player_tokens (token) ON DELETE CASCADE,
  game_token             TEXT NOT NULL,
  local_player_id        TEXT NOT NULL,
  eligible_team_ids_json TEXT,            -- LMS only; null for Predictor
  manager_suffix         TEXT,            -- short identifier shown on the PWA
  PRIMARY KEY (token, game_token)
);

CREATE INDEX IF NOT EXISTS idx_game_enrollments_game ON game_enrollments (game_token);

-- ── Round pushes ──────────────────────────────────────────────────────────────
-- One row per game's currently open round. Upserted on every push.
CREATE TABLE IF NOT EXISTS round_pushes (
  game_token    TEXT PRIMARY KEY,
  mode          TEXT NOT NULL,            -- 'lms' | 'predictor' | 'killer'
  round_number  INTEGER NOT NULL,
  deadline      TEXT,                     -- ISO8601 UTC; null if unset
  game_name     TEXT,                     -- the manager's game title, for the PWA card heading
  fixtures_json TEXT NOT NULL,
  joker_enabled INTEGER NOT NULL DEFAULT 0,
  manager_token TEXT,
  warned_at     TEXT,
  updated_at    TEXT NOT NULL,
  -- Opaque, mode-specific round data (unread/unvalidated by the server, like
  -- payload_json below) — e.g. Killer's { phase, otherPlayers }. Null for
  -- LMS/Predictor. Existing on-disk uk/eu DBs need the one-off migration in
  -- migrations/0001_add_round_pushes_extra_json.sql; this CREATE TABLE only
  -- covers fresh databases (CREATE TABLE IF NOT EXISTS is a no-op on an
  -- existing table, so adding a column here does nothing for uk/eu as-is).
  extra_json    TEXT
);

CREATE INDEX IF NOT EXISTS idx_round_pushes_manager ON round_pushes (manager_token);

-- ── Round results ─────────────────────────────────────────────────────────────
-- Last-2-rounds "what happened" per game — survived/eliminated (LMS), points
-- (Predictor), lives/hits (Killer). Written alongside a round_pushes upsert
-- (piggybacked on round-open, game-complete, or a manual resend — never a
-- dedicated push), pruned to the last 2 rows per game_token. Opaque
-- results_json, same pattern as fixtures_json/payload_json/extra_json above.
CREATE TABLE IF NOT EXISTS round_results (
  game_token    TEXT NOT NULL,
  round_number  INTEGER NOT NULL,
  mode          TEXT NOT NULL,
  results_json  TEXT NOT NULL,
  created_at    TEXT NOT NULL,
  PRIMARY KEY (game_token, round_number)
);

-- ── Submissions ───────────────────────────────────────────────────────────────
-- Player self-submissions land here as 'pending'. Manager approves or rejects.
CREATE TABLE IF NOT EXISTS submissions (
  id           TEXT PRIMARY KEY,
  token        TEXT NOT NULL REFERENCES player_tokens (token) ON DELETE CASCADE,
  game_token   TEXT NOT NULL,
  round_number INTEGER NOT NULL,
  payload_json TEXT NOT NULL,
  status       TEXT NOT NULL DEFAULT 'pending',
  submitted_at TEXT NOT NULL,
  decided_at   TEXT,
  UNIQUE (token, game_token, round_number)
);

CREATE INDEX IF NOT EXISTS idx_submissions_token  ON submissions (token);
CREATE INDEX IF NOT EXISTS idx_submissions_game   ON submissions (game_token);
CREATE INDEX IF NOT EXISTS idx_submissions_status ON submissions (status);

-- ── Manager lifecycle ─────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS manager_lifecycle (
  manager_token        TEXT PRIMARY KEY,
  created_at           TEXT NOT NULL,
  unsubscribed_at      TEXT,
  scheduled_delete_at  TEXT,
  max_pwa_links        INTEGER,          -- last-reported Tier.maxPWALinks cap; NULL = unknown/no PWA
  link_cap_warned_at   TEXT              -- when the over-cap grace clock started (separate from scheduled_delete_at)
);

-- ── Manager backups ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS manager_backups (
  manager_token  TEXT NOT NULL,
  restore_code   TEXT NOT NULL,
  backed_up_at   TEXT NOT NULL,
  PRIMARY KEY (manager_token, restore_code)
);

CREATE INDEX IF NOT EXISTS idx_manager_backups_token ON manager_backups (manager_token, backed_up_at DESC);

-- ── Publish links ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS publish_links (
  id                   TEXT PRIMARY KEY,
  pin_salt             TEXT NOT NULL,
  pin_hash             TEXT NOT NULL,
  r2_key               TEXT NOT NULL,
  owner_key_id         TEXT NOT NULL,
  owner_token          TEXT,
  manager_token        TEXT,                -- links this link to its owning manager, for cascade delete
  unlock_attempts      INTEGER NOT NULL DEFAULT 0,
  unlock_locked_until  TEXT,
  created_at           TEXT NOT NULL,
  updated_at           TEXT NOT NULL
);
