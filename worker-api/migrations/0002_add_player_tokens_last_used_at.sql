-- One-off migration for existing uk/eu D1 databases (schema.sql's CREATE
-- TABLE IF NOT EXISTS is a no-op against a table that already exists, so the
-- new `last_used_at` column on `player_tokens` has to be added here instead).
--
-- SQLite/D1 doesn't support `ADD COLUMN IF NOT EXISTS`, so this errors with
-- "duplicate column name" if run twice against the same database — run it
-- once per region, not as part of the repeatable `db:migrate:*` scripts.
--
-- Apply manually, per region, before deploying the worker-api version that
-- reads/writes this column:
--   wrangler d1 execute lsm-api-uk-db --remote --env uk --file=./migrations/0002_add_player_tokens_last_used_at.sql
--   wrangler d1 execute lsm-api-eu-db --remote --env eu --file=./migrations/0002_add_player_tokens_last_used_at.sql

ALTER TABLE player_tokens ADD COLUMN last_used_at TEXT;
