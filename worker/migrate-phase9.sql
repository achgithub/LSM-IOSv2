-- Phase 9: drop dormant Cloud Backup/Publish tables from the sports shards
-- These are orphaned leftovers from before the feature moved wholesale to
-- worker-api (the authority) — no code in this shard has read or written
-- them since (worker/src/index.ts only mounts ./routes/data and ./routes/admin).
-- manager_backups was always empty here; publish_links held 8 rows of dev/test
-- data from 2026-06-25/26, none since.
-- Apply with:
--   npx wrangler d1 execute lsm-uk-db --remote --file migrate-phase9.sql
--   npx wrangler d1 execute lsm-eu-db --remote --file migrate-phase9.sql

DROP TABLE IF EXISTS manager_backups;
DROP TABLE IF EXISTS publish_links;
