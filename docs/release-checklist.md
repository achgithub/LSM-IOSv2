# Release Checklist

Status: **in progress** — TestFlight first, then App Store.

Sources: App Store review, security review, iOS audit, Swift review (all 2026-06-26).

---

## TestFlight Gate

Items that must be done before a TestFlight build is distributed.

### P0 — Blocking (functional correctness)

- [x] **Fix Predictor partial-close bug**
  - `PredictorResultsEntryView` removed the `allScoresSet` guard; Close Round is now enabled with zero or partial scores.
  - Fix: reinstate `allScoresSet` check in the view (gate the button) *and* enforce in `PredictorScoringService` (throw `incompleteScores` if not all fixtures have scores at close time).
  - Distinguish `nil` (blank) from `(0, 0)` (explicitly entered zero-zero).
  - Files: `Modes/Predictor/Rounds/PredictorResultsEntryView.swift`, `Core/Engine/PredictorScoringService.swift`

- [x] **Add Predictor partial-save and close-validation tests**
  - `saveScoresDoesNotCloseRound` — save one score, expect round still open, `pointsAwarded` still nil.
  - `closeRoundRequiresEveryFixtureScore` — partial scores present, expect close throws/fails.
  - `zeroZeroCountsAsEnteredScore` — `(0, 0)` must satisfy the completeness check.

### P1 — Blocking (data safety)

- [x] **Fix cloud unsubscribe lifecycle**
  - `hasCloudBundle` defaults to `false`; RevenueCat refresh failures are swallowed; `CloudBackupSection` calls `/manager/unsubscribe` on any `canUseCloud == false`, which can schedule real data deletion for a paying user on a poor network.
  - Fix: tri-state `CloudEntitlementState` (`.unknown`/`.active`/`.inactive`); unsubscribe only called when `.inactive` (positively confirmed). RevenueCat webhook path deferred.
  - Files: `Monetization/Entitlements.swift`, `Monetization/PurchaseService.swift`, `Shared/Settings/CloudBackupSection.swift`

- [x] **Flip Worker App Attest to production and enforce on protected routes**
  - Worker shard config says `APP_ATTEST_ENV = development` — must be `production` before TestFlight (TestFlight uses production attestations, not development ones).
  - Client and Worker both have the code; the live router doesn't mount `/attest/*` or apply `requireAttestation` yet.
  - Routes protected: `backup/*`, `publish` (POST), manager lifecycle endpoints (`/manager/*`), `/leagues/:id/scores`, `/leagues/:id/fixtures`.
  - Routes kept public: `/leagues.json`, `/s/:token`, `/publish/:id/unlock`, `/leagues/:id/teams`, `/leagues/:id/standings`.
  - Files: `worker/wrangler.jsonc`, `worker/src/index.ts`, `worker/src/routes/backup.ts`, `worker/src/routes/publish.ts`, `worker/src/routes/data.ts`, `worker/worker-configuration.d.ts`
  - **Pre-deploy gate**: confirm `ATTEST_CHALLENGE_KEY` is set as a secret on both `uk` and `eu` shards (`wrangler secret put ATTEST_CHALLENGE_KEY --env uk` / `--env eu`) and `ATTEST_DEV_BYPASS` is absent/empty in prod environments. If `ATTEST_CHALLENGE_KEY` is missing the challenge endpoint throws and every protected route 500s.

- [x] **Add manager ownership checks to manager submission endpoints** (partial)
  - Player PWA links expose `gameToken`; anyone who traces the PWA can attempt manager-only calls.
  - Done: manager lifecycle routes (`/manager/*`) now require App Attest via `requireAttestation` middleware — the genuine app is the only caller.
  - Deferred: server-side check that `gameToken` belongs to the calling `managerToken` (requires a D1 `games`→`manager_token` join that the current games.ts layer doesn't implement yet).

- [ ] **Add server-side entitlement checks for paid cloud features**
  - Modified app can bypass client-side paywall and call `/backup`, `/publish`, `/links` directly.
  - App Attest enforcement (above) ensures only the genuine binary can call these routes, which significantly raises the bar. Full server-side RevenueCat entitlement verification requires a RevenueCat REST API integration that doesn't exist today — defer to App Store gate.

- [x] **Rate-limit published PIN unlock endpoint**
  - `/publish/:id/unlock` has no rate limiting. Short numeric PINs can be scripted through all combinations.
  - Fix: per-link attempt counter in D1 (`unlock_attempts`, `unlock_locked_until`); 429 after 10 failures with 30-minute lockout. Apply `migrate-phase7.sql`.
  - File: `worker/src/routes/publish.ts`

- [x] **Move manager token from UserDefaults to Keychain**
  - `ManagerToken` stored in `UserDefaults`. It acts as an ownership credential for cloud backup/lifecycle.
  - Fix: Keychain storage with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`; reads old UserDefaults value once on first access and migrates, then deletes from UserDefaults.
  - File: `ios/LSM/LSM/Cloud/ManagerToken.swift`

- [ ] **Protect backup overwrites with owner token**
  - Restore UUID is currently both the read and write credential. Anyone with the code can overwrite the backup.
  - Mitigated: PUT /backup/:id now requires App Attest (the genuine app is the only writer). Full separation of restore (read) and owner (write) credentials is a deeper schema change — defer to App Store gate.
  - Fix remaining: add max body size check and schema validation to the PUT handler.

### P1 — Blocking (release readiness)

- [x] **Worker typecheck must pass**
  - `pnpm typecheck` fails — old v1 routes reference bindings (`FOOTBALL_DATA_TOKEN`, `SCORES`, `LEAGUE_ID`, per-league TTL) that no longer exist in the generated v2 `Env` type.
  - Fix: excluded dormant v1 files from tsconfig; removed `getLeagueConfig`/`LeagueConfig` from types.ts; fixed `manifest.ts` `noUncheckedIndexedAccess` error; added `ATTEST_CHALLENGE_KEY` to worker-configuration.d.ts.
  - `pnpm typecheck` now passes clean.

- [x] **Resolve all stale comments**
  - Resolved: `wrangler.jsonc` "FLIP AT RELEASE" comment (removed); `backup.ts`/`publish.ts` "NOT attest-gated" (updated to reflect enforcement); `PurchaseService.swift` debug logging (wrapped in `#if DEBUG`); `PurchaseService.swift`/`Entitlements.swift` placeholder comments updated to say "verify against dashboard".
  - NOT resolved (requires dashboard access): RevenueCat package/entitlement ID confirmation — see next item.
  - `AdUnitIDs.swift` `useTestAds` deferred to App Store gate (not TestFlight).

- [x] **Wrap RevenueCat debug logging in `#if DEBUG`**
  - `Purchases.logLevel = .debug` is unconditional in `PurchaseService.swift`.

- [ ] **Confirm RevenueCat package and entitlement IDs**
  - Comments updated to "verify against dashboard" — identifiers cannot be confirmed without dashboard access.
  - Action needed: log into RevenueCat dashboard and verify `cloud_bundle` (entitlement), `cloud_bundle_monthly` (package), `no_ads`, `leagues_3_monthly`, `leagues_5_monthly`, `leagues_7_monthly` package IDs match exactly.

- [x] **Add explicit `context.save()` around commit actions**
  - Added `try? context.save()` to: Predictor Close Round (with error handling), Predictor Save Scores, LMS Close Round, Open Round, Declare Winners, and Approve Submission.

- [x] **Add App Attest headers to manager lifecycle calls**
  - `ManagerLifecycleClient.swift` sends only `X-Manager-Token` for `status`, `unsubscribe`, `resubscribe`.
  - Fixed: mirrored `AppAttestService.shared.authorizationHeaders(for:)` pattern from `SnapshotClient`.

### Release readiness / Swift quality (can ship without, but do before wide distribution)

- [ ] **Bind App Attest assertions to the specific request**
  - Signed payload should include method, path, body SHA-256, and timestamp — not just a generic challenge.

- [ ] **Enable Swift 6 strict concurrency warnings; add `Sendable` to DTOs**
  - Start with warnings, not enforcement. Add `Sendable` to `MatchDTO`, `TeamDTO`, `StandingDTO`, `ScoreDTO`, submission structs, cache payload structs.

- [ ] **Snapshot SwiftData models before async tasks**
  - Some `Task { }` closures capture live SwiftData model objects. Snapshot to plain `Sendable` structs before entering async work.

- [ ] **Large views: extract when touching**
  - `MatchesView`, `OpenRoundView`, `PlayersView`, `NewGameView` — refactor on contact, not as a standalone rewrite.

---

## App Store (Production) Gate

Additional items required before App Store submission. Everything in the TestFlight gate is also required.

- [ ] **Update privacy policy**
  - Policy currently says all data is local. App now uploads player names, game state, picks, predictions, scores, and standings via Cloud Backup and Publish.
  - File: `web/site/lsm/privacy.html`
  - Must cover: Cloud Backup, Publish, player submission links, data retention, deletion, restore codes, PIN-protected publish pages, RevenueCat, AdMob, App Attest. Be clear cloud features are optional.

- [ ] **Update App Store Connect App Privacy disclosures** to match real data flows.

- [ ] **Make Cloud Bundle paywall subscription-compliant**
  - Currently shows only marketing text and a Subscribe button — missing price, billing period, Restore Purchases, renewal/cancel copy, Terms of Use and Privacy Policy links.
  - Files: `Shared/Settings/CloudBackupSection.swift`, `Shared/Settings/PaywallView.swift`

- [ ] **Switch to production ad unit IDs**
  - `AdUnitIDs.useTestAds = true` is hardcoded. Fix: use build configuration (`#if DEBUG`) rather than a manual pre-release edit.
  - File: `Monetization/AdUnitIDs.swift`

- [ ] **Add `PrivacyInfo.xcprivacy` privacy manifest**
  - Required by Apple for apps using `UserDefaults` and SDKs including Google Mobile Ads and RevenueCat. Missing entirely.

- [ ] **Resolve SwiftLint config reference**
  - `project.pbxproj` points at `$SRCROOT/.swiftlint.yml` which does not exist.

---

## Pricing Review

**Context:** The current pricing model (`docs/pricing-model.md`, decided 2026-06-21) is a leagues-based ladder: Free (ads) → No Ads → 3/5/7 Leagues. Cloud Backup and Publish are currently a separate add-on SKU ("Cloud Bundle") sitting entirely outside this ladder.

**Open question:** Should Cloud Backup/Publish be folded into the league tier ladder, bundled with higher tiers, or remain a standalone add-on?

**Considerations to review:**

- The Cloud Bundle paywall is currently non-compliant (missing price, terms, restore path) — this needs fixing regardless of the pricing decision.
- Cloud Backup protects game data that accumulates over time (rounds, scores, predictions). Its value scales with engagement, not with how many leagues a user follows — different value axis from the league ladder.
- Publish (shared standings/results pages) is a social/sharing feature — could be a meaningful upgrade driver if bundled into a tier rather than sold separately.
- A standalone add-on means a user on the "No Ads" tier could subscribe to Cloud Backup, creating a combination that isn't represented in the current ladder.
- Bundling Cloud Backup into the top tier (7 Leagues) would reduce complexity but lose revenue from users who want cloud but not more leagues.
- RevenueCat supports offering multiple active entitlements — a standalone Cloud Bundle doesn't break the architecture, but it does add a second purchase flow and a second paywall to maintain and keep compliant.

**Decision needed before TestFlight** (so the paywall can be built correctly): keep as standalone add-on, or integrate into the tier ladder.
