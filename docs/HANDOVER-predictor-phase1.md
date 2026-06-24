# Handover — start LSM v2 Predictor build (Phase 1)

Paste the block below into a fresh context to begin the build.

---

```
We're building LSM v2 (iOS app "Last Stand Manager"). This repo is the v2 clone —
fully separate from v1. NEVER touch v1 at /Users/andrewharris/projects/lms-ios
(separate repo, still shipping). We are at /Users/andrewharris/projects/LSM-IOSv2.

## Read first (canonical — don't re-derive)
- docs/lsm-v2-architecture.md — **§0 "Design decisions locked (2026-06-24)" is the
  binding record**; §§1–6 are the older sketch and are annotated where superseded.
- Auto-memory predictor-v2-design — the full Predictor/league/publish/queue design.
- V2-SCAFFOLD.md, ios/LSM/LSM/README.md — repo/app layout.
- To build+run the app: use the /run skill (project skill ios/LSM/.claude/skills/run-lsm
  — drive.sh sim|device; it asks Simulator vs Andrew's iPhone).

## State (done, on github.com/achgithub/LSM-IOSv2, main)
- iOS renamed LSM (bundle com.sportsmanager.LSM); sources in Core/Modes/Cloud/
  Submissions/Shared. App builds, runs, and reads live data from the v2 regional-
  shard workers (lsm-uk/lsm-eu on workers.dev) — verified on simulator + device.
- Read path live; data copied from v1. SCHEMA LESSON: teams keyed (league_id,
  external_id) and standings (league_id, team_id) — composite, never provider-id
  alone (clubs move between co-located leagues, e.g. PL↔ELC).
- All v2 feature design is LOCKED (see §0 / memory). Build NOT started.

## Key locked decisions (the constraints to build within)
- **Game state stays on-device (SwiftData), like v1.** Cloud is thin: only the
  PWA submission inbox (D1, transient), backup snapshots (R2), publish snapshots
  (R2). NO cloud-backed picks/predictions. The v1 sync machinery stays dormant.
- **One `Game` @Model + `mode` discriminator** (.lms|.predictor); both modes share
  the home-screen Games list (mode badge). `GameCloudClient` is a stub.
- Predictor: `Prediction` mirrors `Pick`; scored CLIENT-SIDE at round close;
  fixtures selected like LMS; tiered configurable scoring (Exact>GD>Result+Joker,
  draws inherit GD); implicit last-used settings (no templates).
- Build order: **(1) Predictor on-device → (2) cloud bundle publish+backup (pay-
  only, one entitlement) → (3) PWA + queue last.**

## Immediate task — draft & start Phase 1: Predictor (fully on-device, no cloud)
Produce a concrete build plan, then implement incrementally:
  - `mode` discriminator on `Game` + mode-aware New Game flow (mode picker first)
  - `Prediction` SwiftData model + Predictor scoring engine (tiered, configurable;
    rule table in §0) computed at round close
  - Predictor predictions-entry UI (score per selected fixture) reusing the LMS
    round flow; on-device predictions league table (competition ranking "1,1,3",
    alphabetical within ties) reusing StandingsView look
  - home-screen GameCard mode badge + mode-aware secondary line
Do NOT build any cloud/PWA/publish/backup yet — that's phases 2–3.

Start by reading §0 of the architecture doc and the predictor-v2-design memory,
then propose the Phase-1 build plan before writing code.
```
