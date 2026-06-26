-- Phase 5: joker support + manager suffix for enrollment identity
-- Apply with:
--   npx wrangler d1 execute lsm-uk-db --remote --file migrate-phase5.sql

ALTER TABLE round_pushes ADD COLUMN joker_enabled INTEGER NOT NULL DEFAULT 0;
ALTER TABLE game_enrollments ADD COLUMN manager_suffix TEXT;
