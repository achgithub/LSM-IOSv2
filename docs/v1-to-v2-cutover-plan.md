# v1 → V2 cutover & release sequencing plan

**SUPERSEDED 2026-08-11.** This doc was written before discovering
`worker-api-v2` (a deployed, KV-backed sync Worker with iOS wiring already
in TestFlight build 72) — the sync-backend cutover is the higher-stakes
half of this problem and this version doesn't cover it. The current plan
lives on branch `worktree-agent-a112bd9b78b63937e`, at the same path
(`docs/v1-to-v2-cutover-plan.md`), and should replace this file at merge
time rather than being kept as a second live copy. The UI-cutover
reasoning below is still accurate and carried forward into that version
unchanged.

---

Two separate "v1 → v2" stories exist in this codebase. This plan covers both,
because the terms collide:

1. **Repo/backend v1 → v2** (this whole repo *is* "v2" of the app, forked
   from `lms-ios`). **Already done.** See "Backend cutover" below for the
   two loose ends.
2. **UI redesign v1 → V2** (`RedesignV2/` — the card-based screens, today an
   opt-in "Try the new design" toggle in Settings). **Not done — this is the
   real work.** Everything below "UI cutover" is about this.

Also covers **build-version enforcement**, which is a separate lever
(`VersionGate`) that interacts with the UI cutover only at the rollback
step, not before.

---

## Backend cutover — status: done, two loose ends

Evidence this already shipped (not proposed, verified against current code):

- No `worker-registry/` directory in the repo — the dormant v1 registry
  worker `V2-SCAFFOLD.md` said to "neutralise/delete" is gone.
- `Leagues.swift:116`'s `registryURL` already points at
  `https://uk-api.sportsmanager.site/leagues.json` — the
  `cloudflare-security-audit-2026-07-28` memory says this needed an app
  rebuild; that rebuild has since shipped. **That memory is stale — update
  it** (see end of this doc).
- `worker-dash` was repurposed as `lsm-v2-dash-worker` on its own
  `dash.sportsmanager.site` route rather than deleted.

Two things are still genuinely open:

- **`V2-SCAFFOLD.md` and `worker/MIGRATION.md` still narrate the cutover as
  "outstanding."** Both are stale docs now that the separation is verified
  complete — update or archive them so they stop reading as a live TODO.
- **EU shard manifest parity.** The 2026-07-28 audit moved `SHARD_BASE` to
  custom domains but deployed to the **uk** shard only, "per Andrew's call —
  eu deploy held off." `worker/src/manifest.ts` now unconditionally points
  both `uk` and `eu` at their `*.sportsmanager.site` custom domains in
  source, so confirm the **eu** shard has actually had `wrangler deploy`
  run against this manifest — otherwise eu is silently drifted from what's
  in the repo. This is unrelated to the UI cutover; sequence it whenever,
  no dependency.

No action needed elsewhere on the backend side for the UI cutover — the
V2 screens call the same `GameCloudClient` / worker-api endpoints the v1
screens do. This is a client-only reskin.

---

## UI cutover — what "done" actually requires

**The toggle flip is not the work.** `V2PreviewFlag` currently gates a
`NavigationLink` pushed inside *Settings'* own `NavigationStack`
(`V2PreviewMenuView`, reached via `SettingsView`). `RootTabView` — the
actual app root — has zero V2 references. Making V2 "the default" means
building a V2 root shell and re-wiring everything `RootTabView` owns today,
not just changing which screen a toggle points at.

### What has to move to a V2 root

Everything in `RootTabView.swift` currently sits above/around the tab
content and has no V2 equivalent yet:

- **The entire `.task` startup block** (`RootTabView.swift:89-123`):
  `PurchaseService.shared.configure()`, `AdsBootstrap.start()` +
  `RewardedAdManager.preload()`, `entitlements.refresh()`,
  `enabled.updateGracePeriod()`, `EnabledLeagues.shared.pruneInvalid()`,
  `LeagueData.performFirstLaunchFreeFillIfNeeded()`, and the fire-and-forget
  `Leagues.refreshFromRegistry()` call. Losing any of these on a V2-first
  launch silently breaks purchases, ads, entitlements, or the grace-period
  clock. `refreshFromRegistry()` in particular is what feeds `minVersion`
  into the version gate for the *next* launch — see enforcement section.
- `AdBannerView()` for ad-supported tiers (deliberately a sibling below the
  tab content, not a safe-area inset — same trap noted in `AppRootView`'s
  own banner comment).
- The grace-days-remaining banner, the `ManagerOnboardingView` first-launch
  sheet, and the forced `LeagueDowngradeView` full-screen cover (and the
  `splashActive` gating all three respect so they don't pop over the splash
  screen).
- `.environment(entitlements)` / `.environment(submissionBadgeStore)`
  injection — `V2PreviewMenuView` currently gets `SubmissionBadgeStore` for
  free because it's pushed inside `RootTabView`'s environment. A standalone
  V2 root needs to inject both itself.

**One thing that is already safe and needs no work:** the version-gate hard
block (`VersionGateView`) renders in `AppRootView`, *above* `RootTabView`
entirely (`AppRootView.swift:33-43`). Swapping what sits below it (v1 tabs
vs. a V2 root) doesn't touch it — confirmed by reading the current source,
not assumed.

### Feature-completeness check

`RedesignV2/Screens` has a V2 counterpart for every v1 mode (LMS, Predictor,
Killer) plus Players/Matches/Standings/Settings/Submission Inbox — commit
history (`V2 finish, Phase A/B`, `V2 cross-mode consistency pass`) reads as
a genuine completion pass, not partial coverage, and a grep for
TODO/FIXME/"not yet implemented" inside `RedesignV2/` turns up nothing
actionable (only two unrelated UI copy strings containing the words "not
yet reviewed"). Treat V2 as functionally complete pending real usage,
not pending more building.

### Test coverage gap — real, worth closing before cutover

`ios/LSM/LSMUITests/LMSSmokeUITests.swift` has a test named
`testLeaguesLoadFromV2Workers` — despite the name, "v2" there means the
**backend** shard workers, not the `RedesignV2` UI. There is currently
**no UI test coverage of any `RedesignV2` screen.** Once V2 becomes the
default tab content, the existing smoke test's tab-navigation assumptions
will break (it navigates through v1's tab structure) — treat that failure
as the signal to update it, and add at least one smoke path through the V2
shell (Games → open a game → enter a round) before flipping the default,
not after.

### Sequence

Reasoning for the split: a UI reskin doesn't touch the API contract, so the
cutover release needs **no** `minVersion` bump — reserve that lever for the
day v1 code is actually deleted or a real API break ships. Two releases,
not one:

1. **Now — verify where 1.2 actually is.** Git history shows three
   "Bump build number for TestFlight upload" commits plus a
   `MARKETING_VERSION → 1.2` bump stacked at HEAD; memory says 1.1 went live
   2026-08-11. Confirm 1.2's actual TestFlight/App Store state before
   planning 1.3 on top of it — don't assume from commit messages alone.

2. **Cutover release (1.3): V2 becomes the default root, v1 stays in the
   binary as a dormant fallback.**
   - Build the V2 root shell (tab bar or equivalent + the bootstrap list
     above), wire it in `AppRootView` in place of `RootTabView`.
   - Keep a kill-switch: repurpose `V2PreviewFlag` (inverted) as an
     escape hatch back to the v1 shell, reachable from Settings, rather
     than deleting v1 screens. This is what buys you a same-build revert
     if 1.3 has a launch-day surface bug — old installs on 1.2 are
     unaffected either way, but a 1.3 user who hits a V2-only bug can drop
     back to v1 without waiting on a new App Store review.
   - Update `LMSSmokeUITests` for the new default tab structure; add V2
     smoke coverage (see above).
   - New App Store screenshots (the store listing currently shows v1
     screens).
   - De-hedge `docs/help/faq.md` — its own placeholder note says "add
     screenshots once V2 fully replaces v1"; either this release or the
     next is that point, depending on which you finalize on.
   - **No `minVersion` bump.** Old 1.2 installs keep working against the
     same API unchanged.

3. **Cleanup release (1.4, one release later — not bundled into 1.3):
   delete v1 screens.**
   - Only do this after 1.3 has had a real observation window with no
     rollback needed — old installs on earlier versions carry their own
     compiled copy of v1 regardless of what HEAD looks like, so deleting
     v1 code doesn't retroactively affect anyone; it only removes *your*
     revert path for 1.3. That's the reason to wait a release, not a
     technical dependency.
   - This is also the natural point to raise `minVersion` if you want to
     force stragglers off the pre-redesign v1 UI entirely — see
     enforcement below for the safety rule on doing that.

### Optional: remote same-day rollback lever

App Store review is ~24h+, so a code revert can't ship same-day. If that
matters for 1.3 specifically, add a `v2Default: Bool` field to the
`/leagues.json` manifest already fetched by `refreshFromRegistry()`, cached
in `UserDefaults`, read at launch to decide v1-shell-vs-V2-shell before
first render. Real cost: it's a launch-time decision with no live network
call in the critical path (same constraint the version gate already has,
one-launch-delayed), so it's an *additional* piece of launch-sequencing
logic to build and keep correct — not free. Recommendation: skip it for 1.3
unless you specifically want a kill switch that doesn't require the
in-app Settings toggle (e.g. for a bug that prevents reaching Settings at
all); the in-app toggle from step 2 already covers the common case.

---

## Build-version enforcement

This is the existing `VersionGate` mechanism
(`ios/LSM/LSM/Cloud/VersionGate.swift`), already built and live — nothing
new to write, but two things worth being precise about since "build
version" is ambiguous:

- **It gates `CFBundleShortVersionString`** (`MARKETING_VERSION`, currently
  `1.2`) — **not** `CURRENT_PROJECT_VERSION` (the build number, currently
  `70`). If you need per-build enforcement rather than per-marketing-version,
  that's a different comparison in `VersionGateCheck.isVersion` and a
  different field in the manifest; not built today.
- **It's one launch delayed by design.** `Leagues.refreshFromRegistry()` is
  explicitly fire-and-forget "for the *next* launch" (`RootTabView.swift`
  comment) — raising `minVersion` on the worker doesn't hard-block anyone
  already mid-session; it takes effect on their next cold start. Don't plan
  around it as an immediate kill switch.

**Hard rule when raising `minVersion` in `worker/src/manifest.ts`:** only
raise it to a version that is *already live and downloadable* in the App
Store, with a propagation buffer after confirming that. `VersionGateCheck`
is deliberately non-dismissible (`VersionGateView` has no skip) — raising
`minVersion` to a version still "In Review" or "Pending Release" hard-locks
every installed copy of the app out of functioning, with no way for a user
to comply, until that version actually goes live. `isVersion` fails open on
unparseable input, and `clear()` correctly un-blocks if the value is later
lowered — so the mechanism itself is safe to experiment with; the discipline
is entirely in the manifest value you deploy.

Because it's a worker redeploy against `uk-api.sportsmanager.site` (the
only shard URL baked into the binary — `Leagues.swift:116`), raising or
lowering `minVersion` is reversible without an app release, unlike
everything in the UI cutover section above.

**Recommendation for this sequence specifically:** don't touch `minVersion`
for the 1.3 cutover release (no API break). Consider raising it only at
step 3 (1.4, v1 deletion) if you want to force very old installs forward —
and only once 1.4 itself is confirmed live in the App Store, per the rule
above.

---

## Memory to update after this plan is acted on

`cloudflare-security-audit-2026-07-28`'s "Remaining — needs an app-code
change + rebuild" item (the `registryURL` hardcoded to `workers.dev`) is
resolved in current code — `Leagues.swift:116` already points at
`uk-api.sportsmanager.site`. That memory should be corrected once this plan
is reviewed, not carried forward as an open item.
