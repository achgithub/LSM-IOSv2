# v1 → V2 cutover & release sequencing plan

**Source of truth lives here, on `worktree-agent-a112bd9b78b63937e`** — this is
where `worker-api-v2` actually lives. An earlier version of this doc was
committed to `main`'s `docs/`; that copy is marked superseded and should be
replaced by this one at merge time, not kept as a second live doc.

Two separate cutovers are in flight and get conflated because both are
called "v1 → v2":

1. **UI redesign** (`RedesignV2/` — card-based screens, opt-in Settings
   toggle today). Client-side only, no backend involvement. See "UI
   cutover" (§3) — unchanged since the first pass.
2. **Sync backend: D1 → KV** (`worker-api` → `worker-api-v2`). The real,
   high-stakes piece: `worker-api-v2` is deployed (real KV namespace,
   `api-v2.uk.sportsmanager.site`), and iOS wiring to it (`SyncCoordinator`)
   has shipped to TestFlight — build 72, MARKETING_VERSION 1.2, branch
   `worktree-agent-afe878ae4dcfb9048`. **Live App Store build is 69, which
   predates this feature entirely and is unaffected.** This section (§1-2)
   is the actual design, agreed 2026-08-11.

---

## 0. Known rough edge in the V2 preview — not urgent

`SyncCoordinator.sync()` pushes open rounds to `worker-api-v2` (KV) via a
hardcoded override; `mintLink` always mints PWA links against `worker-api`
(D1). Reachable only from the RedesignV2-only Sync button, gated behind the
opt-in "Try the new design" toggle — a feedback-only preview, not where
active games are expected to run. D1 is never touched by the KV push, so
nothing is lost — a manual v1 "Resend to Player App" fully recovers it in
one tap. Not urgent; resolves by construction once §1 ships and
`SyncCoordinator` drops the hardcoded override.

---

## 1. Design: server-side per-game routing flag (the agreed approach)

**The constraint that shapes everything:** the player's PWA has
`api.uk.sportsmanager.site` hardcoded in its deployed bundle
(`player-app/src/api.ts:6`) — it can never be told to call a second host
without a PWA redeploy. So `worker-api` stays the **one public hostname,
forever**, for every client, every app version, both UIs. Nothing about
this design ever asks the PWA or an old app build to know `worker-api-v2`
exists.

**Routing mechanism:** each game gets a `storageVersion: d1 | kv` flag,
stored as one column in the small D1 index `worker-api` already consults
per request. `worker-api` checks the flag and either serves from its own
D1 directly, or forwards to `worker-api-v2` via a Cloudflare **service
binding** (worker-to-worker — confirmed free of any extra request charge,
see §4) and returns its response unchanged. `/attest/*` and `/admin/*`
stay on `worker-api` only, untouched — `worker-api-v2` was deliberately
built with no attest routes at all, so this split is clean and permanent.

This is deterministic (a direct flag check, not a "try D1, fall back to
KV" probe), and it's entirely server-side — no client, old or new, v1 UI
or V2 UI, needs to know or care which store backs a given game. That's
what makes it genuinely seamless rather than just "less risky": the
routing decision belongs to `worker-api`, not to whichever build happened
to create the game.

**New games:** minted with `storageVersion: kv` from creation, once
`worker-api` is set to do that by default. No drain needed, nothing
pending yet.

**Existing games — the drain step, this is what makes moving them safe:**
1. Fetch that gameToken's pending D1 submissions
   (`GET /games/:gameToken/submissions`).
2. If any exist, surface them through the existing approve/reject queue
   UI (`SubmissionQueueView` / `SubmissionInboxViewV2` — no new screen
   needed) and block the flip until the list is empty.
3. Once zero pending, flip that game's flag to `kv`. From the next push
   onward its `round_push`/`submissions` live in KV.
4. Old D1 rows for that game go dead — nothing reads them again. Leave
   them; don't bother reconciling or copying.

The player never sees any of this. Same URL, same response shape,
throughout — only what's happening behind that one URL changes.

**Why no `minVersion` bump, ever, for this:** the public contract never
changes shape. A ten-year-old build hitting `POST /links` gets routed by
whatever `worker-api` currently decides — the client was never coupled to
storage internals in the first place.

---

## 2. Endgame: cleaning up D1

**Trigger is a data check, not a version check.** Once a query for
`storageVersion = d1` (or unflagged) returns zero rows — every existing
game has been drained and flipped — nothing reads `round_pushes`,
`submissions`, `game_enrollments`, `player_tokens`, or
`manager_lifecycle` in D1 anymore. Drop those tables. This can happen as
soon as drains are done, independent of how many app-version updates
customers have or haven't installed — App Store Connect adoption numbers
are the wrong metric to wait on here, since routing was never
client-version-dependent.

**What doesn't go away: `worker-api` itself.** It keeps owning
`/attest/*` (device registry + JWT issuance) and its own small
`attest_devices` D1 table — untouched by any of this, and not something
`worker-api-v2` was ever meant to duplicate. Retiring `worker-api`
entirely (collapsing to one Worker, repointing the hostname straight at
`worker-api-v2`) would require porting attestation there too — real,
separate, out-of-scope work, not part of this plan. Realistic end state:
`worker-api` becomes a thin permanent front door — `/attest/*` served
directly, everything else forwarded — not a Worker that disappears.

**Cost is not a factor in any of this**, checked against current
Cloudflare docs: Workers billing is aggregate per-account (10M
requests + 30M CPU-ms/month included, pooled across every Worker script,
no per-script fee), and service-binding calls between `worker-api` and
`worker-api-v2` carry no extra request charge. The only line item worth
watching if usage scales way up is KV's per-write cost ($5/million past
the first million free) — and that scale of usage implies a subscriber
base large enough that the cost is noise against revenue.

**Open, still Andrew's call:** KV TTLs — `CONTENT_TTL_SECONDS` (100 days,
refreshed on touch) and `SUBMISSION_TTL_SECONDS` (30 days, not refreshed
on read) — vs. D1 rows, which never expired in practice (the D1 cleanup
cron was built but never activated). Decide before real games start
writing through to KV, not after.

---

## 3. UI cutover (independent of §1-2, unchanged from the first pass)

Works identically regardless of which store backs a given game, since §1
keeps the wire contract stable either way.

**The toggle flip is not the work.** `RootTabView` — the actual app root —
has no V2 wiring today; `V2PreviewFlag` only gates a `NavigationLink`
inside Settings. Making V2 the default means building a V2 root shell that
owns everything `RootTabView` currently does: the full `.task` startup
block (purchases, ads, entitlements refresh, grace-period clock, league
pruning, first-launch fill, `Leagues.refreshFromRegistry()` — which also
feeds `minVersion`), the ad banner, the onboarding sheet, the forced
league-downgrade cover, and the `entitlements`/`submissionBadgeStore`
environment injection `V2PreviewMenuView` currently gets for free. The
version-gate hard block itself needs no changes — it renders in
`AppRootView`, above `RootTabView` entirely (`AppRootView.swift:33-43`).

V2 is feature-complete across LMS/Predictor/Killer (no TODOs found in
`RedesignV2/`). The one real gap: **no UI test coverage of any
`RedesignV2` screen** — `LMSSmokeUITests.testLeaguesLoadFromV2Workers`
tests the backend v2 shards, not the RedesignV2 UI, despite the name. Add
V2 smoke coverage before flipping the default.

---

## 4. Combined release sequence

Two independent parallel tracks — a problem in one shouldn't block or
entangle the other. `minVersion` stays untouched by both.

**Backend track:**
1. Add the service binding from `worker-api` to `worker-api-v2`; add the
   `storageVersion` column to `worker-api`'s game index.
2. Read path first: `GET /s/:token` branches on the flag. Verify against a
   small number of real new games.
3. Extend to write paths (`/links`, `/games/*/push`,
   `/games/*/submissions/*`).
4. Build the drain flow (§1) for flipping existing games.
5. Decide the TTL question (§2) before making `kv` the default for new
   games.
6. `SyncCoordinator` drops its hardcoded `v2BaseURL` and calls `worker-api`
   like every other client path — §0's rough edge stops being possible.
7. Once `storageVersion = d1` rows hit zero, drop the dead D1 tables (§2).

**UI track:**
1. Confirm where 1.2 actually sits in TestFlight/App Store review before
   planning 1.3.
2. 1.3: V2 becomes the default root shell, v1 kept dormant as a
   Settings-reachable fallback. Add V2 UI smoke coverage. New App Store
   screenshots. De-hedge `docs/help/faq.md`.
3. 1.4 (one release later, once 1.3 is confirmed stable): delete v1
   screens. Old installs are unaffected regardless, since they carry their
   own compiled copy.

**Backend cleanup, unrelated to either track, sequence whenever:**
`V2-SCAFFOLD.md` / `worker/MIGRATION.md` still narrate the *original*
repo-level v1→v2 separation (this repo vs. `lms-ios`) as outstanding —
that's actually done (no `worker-registry/` dir, `Leagues.swift` already
repoints at the custom domain). Update those docs. Confirm the eu shard's
custom-domain route was actually deployed (2026-07-28 audit did uk only).

---

## 5. Open decisions for Andrew

- KV TTL values (§2) — keep 100d/30d, or change before real games write
  through to KV.
- Sign off on §1's design (server-side flag + drain) as final, or flag
  anything that still doesn't sit right before implementation starts.
