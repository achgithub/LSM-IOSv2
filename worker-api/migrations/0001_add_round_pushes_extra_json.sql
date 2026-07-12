-- One-off migration for existing uk/eu D1 databases (schema.sql's CREATE
-- TABLE IF NOT EXISTS is a no-op against a table that already exists, so the
-- new `extra_json` column on `round_pushes` has to be added here instead).
--
-- SQLite/D1 doesn't support `ADD COLUMN IF NOT EXISTS`, so this errors with
-- "duplicate column name" if run twice against the same database — run it
-- once per region, not as part of the repeatable `db:migrate:*` scripts.
--
-- Apply manually, per region, before deploying the worker-api version that
-- reads/writes this column:
--   wrangler d1 execute lsm-api-uk-db --remote --env uk --file=./migrations/0001_add_round_pushes_extra_json.sql
--   wrangler d1 execute lsm-api-eu-db --remote --env eu --file=./migrations/0001_add_round_pushes_extra_json.sql

ALTER TABLE round_pushes ADD COLUMN extra_json TEXT;
