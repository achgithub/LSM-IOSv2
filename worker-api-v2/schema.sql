-- LSM API v2 — D1 schema
--
-- This is a brand-new database, separate from worker-api's lsm-api-uk-db —
-- it exists only to back attest_devices (App Attest device registry), the
-- one piece of worker-api-v2 that intentionally stayed on D1 rather than
-- moving to KV (see wrangler.jsonc's header comment). Everything else
-- (links, rounds, submissions, manager lifecycle) lives in SUBMISSIONS_KV —
-- see src/kv/keys.ts.
--
-- Fresh database, so this is the full shape up front (worker-api's
-- migrations/0004_add_attest_devices_manager_token.sql is already folded
-- into the CREATE TABLE below — no migrations directory needed here).
--
-- Apply:
--   pnpm db:migrate:uk

PRAGMA foreign_keys = ON;

-- ── App Attest devices ────────────────────────────────────────────────────────
-- One row per enrolled device. Registration happens once (per device per
-- authority); assertions are verified on every /attest/assert call and the
-- sign counter advances.
CREATE TABLE IF NOT EXISTS attest_devices (
  key_id      TEXT PRIMARY KEY,
  public_key  TEXT NOT NULL,              -- base64 raw uncompressed P-256 point
  sign_count  INTEGER NOT NULL DEFAULT 0,
  environment TEXT NOT NULL,              -- 'production' | 'development'
  manager_token TEXT,                     -- links this device to its owning manager, for cascade delete
  created_at  TEXT NOT NULL,
  updated_at  TEXT NOT NULL
);
