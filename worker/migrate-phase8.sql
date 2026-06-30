-- Phase 8: manager display name on player tokens
-- Enables the PWA to show "Manager: XYZ" and the saved app name "LSM XYZ".
-- Apply with:
--   npx wrangler d1 execute lsm-uk-db --remote --file migrate-phase8.sql
--   npx wrangler d1 execute lsm-eu-db --remote --file migrate-phase8.sql

ALTER TABLE player_tokens ADD COLUMN manager_name TEXT;
