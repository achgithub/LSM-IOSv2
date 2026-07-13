-- One-off migration for existing uk/eu D1 databases (schema.sql's CREATE
-- TABLE IF NOT EXISTS is a no-op against a table that already exists, so the
-- new `manager_token` column on `publish_links` has to be added here instead).
--
-- SQLite/D1 doesn't support `ADD COLUMN IF NOT EXISTS`, so this errors with
-- "duplicate column name" if run twice against the same database — run it
-- once per region, not as part of the repeatable `db:migrate:*` scripts.
--
-- Apply manually, per region, before deploying the worker-api version that
-- reads/writes this column:
--   wrangler d1 execute lsm-api-uk-db --remote --env uk --file=./migrations/0003_add_publish_links_manager_token.sql
--   wrangler d1 execute lsm-api-eu-db --remote --env eu --file=./migrations/0003_add_publish_links_manager_token.sql

ALTER TABLE publish_links ADD COLUMN manager_token TEXT;
