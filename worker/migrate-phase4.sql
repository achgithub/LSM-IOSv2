-- Phase 4 migration: replace per-(game,player) tokens with one global token per player.
-- This drops player_links/submissions and creates player_tokens/game_enrollments/submissions.
-- Safe: all existing player_links rows are test data (confirmed wipe OK).
--
-- Apply:
--   npx wrangler d1 execute lsm-uk-db --env uk --remote --file=./migrate-phase4.sql

PRAGMA foreign_keys = OFF;

DROP TABLE IF EXISTS submissions;
DROP TABLE IF EXISTS player_links;

PRAGMA foreign_keys = ON;

-- One row per player in the manager's roster. Token is the unguessable
-- credential shared with the player (one link, all games).
CREATE TABLE player_tokens (
  token       TEXT PRIMARY KEY,
  player_name TEXT NOT NULL,
  created_at  TEXT NOT NULL,
  revoked_at  TEXT
);

-- Per-(player, game) enrollment. Mint once, enroll per round push.
-- eligible_team_ids_json is LMS-only; null for Predictor.
CREATE TABLE game_enrollments (
  token                  TEXT NOT NULL REFERENCES player_tokens (token) ON DELETE CASCADE,
  game_token             TEXT NOT NULL,
  local_player_id        TEXT NOT NULL,
  eligible_team_ids_json TEXT,
  PRIMARY KEY (token, game_token)
);

CREATE INDEX IF NOT EXISTS idx_game_enrollments_game ON game_enrollments (game_token);

-- Submission queue. PK includes game_token so John in game A and game B
-- can both submit for round N without conflicting.
CREATE TABLE submissions (
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
