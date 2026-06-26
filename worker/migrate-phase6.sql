-- Phase 6: manager identity, lifecycle tracking, and data retention
-- Apply with:
--   npx wrangler d1 execute lsm-uk-db --remote --file migrate-phase6.sql

-- Tie each game push and each player token to the manager who created it.
ALTER TABLE round_pushes   ADD COLUMN manager_token TEXT;
ALTER TABLE round_pushes   ADD COLUMN warned_at     TEXT;
ALTER TABLE player_tokens  ADD COLUMN manager_token TEXT;

-- Manager lifecycle — unsubscribe grace period + abandonment warnings.
-- One row per manager; created lazily on first backup or push.
CREATE TABLE IF NOT EXISTS manager_lifecycle (
  manager_token        TEXT PRIMARY KEY,
  created_at           TEXT NOT NULL,
  unsubscribed_at      TEXT,                    -- when subscription lapsed
  scheduled_delete_at  TEXT                     -- unsubscribed_at + 14 days
);

-- Audit log of backup blobs so the cron can prune beyond the last 2 per manager.
CREATE TABLE IF NOT EXISTS manager_backups (
  manager_token  TEXT NOT NULL,
  restore_code   TEXT NOT NULL,
  backed_up_at   TEXT NOT NULL,
  PRIMARY KEY (manager_token, restore_code)
);

CREATE INDEX IF NOT EXISTS idx_round_pushes_manager   ON round_pushes  (manager_token);
CREATE INDEX IF NOT EXISTS idx_player_tokens_manager  ON player_tokens (manager_token);
CREATE INDEX IF NOT EXISTS idx_manager_backups_token  ON manager_backups (manager_token, backed_up_at DESC);
