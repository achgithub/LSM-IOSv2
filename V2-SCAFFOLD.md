# LSM v2 — scaffold summary

This repo (`LSM-IOSv2`) is the v2 of the app, **cloned from v1 with full history**
preserved (fork point: `c7f6a7a`) and `origin` re-pointed to a fresh GitHub repo.
v1 (`lms-ios`) is untouched and keeps shipping independently. See
`docs/lsm-v2-architecture.md` for the design.

## Decisions locked (2026-06-24)

- **Repo:** clean clone, history kept; v2 diverges from here.
- **Bundle id:** `com.sportsmanager.LSM` (v1 is `com.sportsmanager.LMS`).
  Display name "Last Stand Manager". Target/scheme renamed `LMS` → `LSM`.
- **Data topology:** regional shards. Start with **UK + Europe** only, seeded by
  copying v1's per-league D1s across (`worker/MIGRATION.md`). Revisit Cloudflare
  provisioning + URL repoint later.

## What was scaffolded

- **iOS** (`ios/LSM/`): renamed target/dirs/bundle id; sources reorganised into
  `Core` / `Modes/{LMS,Predictor}` / `Cloud` / `Submissions` / `Shared`
  (see `ios/LSM/LSM/README.md`). Project parses (`xcodebuild -list` → target `LSM`).
  New skeletons: `GameMode`, `PredictorHomeView`, `GameCloudClient`,
  `SubmissionQueueView`.
- **Worker** (`worker/`): v2 `schema.sql` (multi-league-per-shard + new
  `games`/`players`/`picks`/`predictions`/`submission_tokens`/`submissions`
  tables); `wrangler.jsonc` with **uk + eu** shard envs (placeholder D1 ids);
  `src/shards.ts` league→shard manifest; route stubs
  `src/routes/{games,submissions}.ts`; one-off copier `scripts/seed-from-v1.mjs`.
- **PWA** (`player-app/`): anonymous UUID-link submission surface skeleton.

## Outstanding — the v1 → v2 cut-over

The plan is: **(1) one-off copy v1 data into the v2 shards, then (2) fully
separate.** Both steps are in `worker/MIGRATION.md`.

> ⚠️ Until separation is done, the v2 clone still carries v1's **live** Cloudflare
> configs in `worker-registry/` and `worker-dash/` (real D1 ids + `sportsmanager.site`
> routes). They're separate *files*, but they still point at v1's production cloud —
> do **not** `wrangler deploy` from those two dirs in this clone until they're
> re-pointed/neutralised. `worker/wrangler.jsonc` is already placeholders-only.

### Step 1 — copy (needs `wrangler login`; creates real v2 D1s)
`worker/MIGRATION.md` → "The one-off copy". Reads v1 read-only; regenerates
`league_id`-stamped INSERTs into `lsm-uk-db` / `lsm-eu-db`.

### Step 2 — full separation (after the copy verifies)
`worker/MIGRATION.md` → "Full separation": delete `worker/scripts/seed-from-v1.mjs`
+ `worker/_seed/`, and neutralise/delete `worker-registry` + `worker-dash`, then
grep-confirm no `lms-*-db` / `sportsmanager.site` references remain in v2.
