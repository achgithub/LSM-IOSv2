-- One-off migration for existing uk/eu D1 databases (schema.sql's CREATE
-- TABLE IF NOT EXISTS is a no-op against a table that already exists, so the
-- new `max_pwa_links`/`link_cap_warned_at` columns on `manager_lifecycle`
-- have to be added here instead).
--
-- SQLite/D1 doesn't support `ADD COLUMN IF NOT EXISTS`, so this errors with
-- "duplicate column name" if run twice against the same database — run it
-- once per region, not as part of the repeatable `db:migrate:*` scripts.
--
-- Apply manually, per region, before deploying the worker-api version that
-- reads/writes these columns:
--   wrangler d1 execute lsm-api-uk-db --remote --env uk --file=./migrations/0005_add_manager_lifecycle_link_cap.sql
--   wrangler d1 execute lsm-api-eu-db --remote --env eu --file=./migrations/0005_add_manager_lifecycle_link_cap.sql

ALTER TABLE manager_lifecycle ADD COLUMN max_pwa_links INTEGER;
ALTER TABLE manager_lifecycle ADD COLUMN link_cap_warned_at TEXT;
