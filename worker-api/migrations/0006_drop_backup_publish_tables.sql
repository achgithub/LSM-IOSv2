-- Drops the tables backing Cloud Backup and Cloud Publish, both removed
-- 2026-08-02 to shed R2 as a dependency ahead of launch (Publish was already
-- unreachable from any app UI; Backup is being replaced by a per-game
-- export/import feature, not yet built).
--
-- Apply manually, before deploying the worker-api version that no longer
-- reads/writes these tables:
--   wrangler d1 execute lsm-api-uk-db --remote --env uk --file=./migrations/0006_drop_backup_publish_tables.sql
--
-- uk-only — the eu authority env was torn down 2026-08-02 (never deployed),
-- so there's no lsm-api-eu-db to run this against.

DROP TABLE IF EXISTS manager_backups;
DROP TABLE IF EXISTS publish_links;
