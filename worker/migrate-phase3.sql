-- Phase 3 migration: drop old submission_tokens/submissions, create player_links/round_pushes/submissions.
-- Safe: both tables have zero real rows (all handlers were 501 stubs).
--
-- Apply:
--   wrangler d1 execute lsm-uk-db --env uk --remote --file=./migrate-phase3.sql

PRAGMA foreign_keys = OFF;

DROP TABLE IF EXISTS submissions;
DROP TABLE IF EXISTS submission_tokens;

PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS player_links (
  token                  TEXT PRIMARY KEY,
  game_token             TEXT NOT NULL,
  local_player_id        TEXT NOT NULL,
  player_name            TEXT NOT NULL,
  eligible_team_ids_json TEXT,
  created_at             TEXT NOT NULL,
  revoked_at             TEXT
);

CREATE INDEX IF NOT EXISTS idx_player_links_game   ON player_links (game_token);
CREATE INDEX IF NOT EXISTS idx_player_links_player ON player_links (game_token, local_player_id);

CREATE TABLE IF NOT EXISTS round_pushes (
  game_token    TEXT PRIMARY KEY,
  mode          TEXT NOT NULL,
  round_number  INTEGER NOT NULL,
  deadline      TEXT,
  fixtures_json TEXT NOT NULL,
  updated_at    TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS submissions (
  id           TEXT PRIMARY KEY,
  token        TEXT NOT NULL REFERENCES player_links (token) ON DELETE CASCADE,
  round_number INTEGER NOT NULL,
  payload_json TEXT NOT NULL,
  status       TEXT NOT NULL DEFAULT 'pending',
  submitted_at TEXT NOT NULL,
  decided_at   TEXT,
  UNIQUE (token, round_number)
);

CREATE INDEX IF NOT EXISTS idx_submissions_token  ON submissions (token);
CREATE INDEX IF NOT EXISTS idx_submissions_status ON submissions (status);
