-- Phase 7: rate-limit the PIN unlock endpoint
-- Apply with:
--   npx wrangler d1 execute lsm-uk-db --remote --file migrate-phase7.sql
--   npx wrangler d1 execute lsm-eu-db --remote --file migrate-phase7.sql

-- Track consecutive failed PIN attempts per publish link so the unlock
-- endpoint can return 429 after repeated failures. Resets on success.
ALTER TABLE publish_links ADD COLUMN unlock_attempts    INTEGER NOT NULL DEFAULT 0;
ALTER TABLE publish_links ADD COLUMN unlock_locked_until TEXT;   -- ISO8601 UTC; NULL = not locked
