# Auto-refresh policy for subscribers (foreground + Open Round)

Status: **draft design, not yet implemented** (2026-08-27, extended 2026-08-30).

## Scope: V2 screens only (2026-08-30)

All screen-triggered wiring in this doc targets **V2 screens only**
(`OpenRoundViewV2`, `KillerOpenRoundViewV2`, and the V2 live-match views below).
The V1 equivalents (`Shared/Rounds/OpenRoundView.swift`,
`Modes/Killer/Rounds/KillerOpenRoundView.swift`) are **not** wired up — they
keep today's manual-only behavior. The app-level foreground trigger
(`scenePhase == .active` in `RootTabView.swift`) is inherently global since V2
is the app root post-cutover, but any `.onAppear`-based trigger is added only
to V2 screen files. Confirmed with Andrew, 2026-08-30, alongside two
additional rules below (live-match tight polling, 12h staleness ceiling) —
also chose **foreground-only**, no `BGTaskScheduler`/background modes.

## Core principle: one trigger mechanism, always client-initiated (added 2026-08-30)

Every sync in this doc — relaxed ladder, live-poll loop, the Home results
widget below — is triggered by the **client**, never by an autonomous
server-side timer/cron reaching out on its own. This is a hard constraint,
not a preference: Free's entire CF-cost-recovery model depends on the
interstitial ad being the thing that gates every Worker call for that tier
(`AdGate.run`). If the Worker could decide on its own to refresh and push
data, that gate would be bypassable and Free would get free (unpaid-for) CF
usage. So even where the Worker does smart, aggregate work server-side (see
"Home results-in widget" below), it only ever runs in response to a request
the client chose to make — one mechanism, consistently enforced, no second
path that quietly reintroduces server-driven syncing.

Today, refreshing league/team/match data is always an explicit user action
(`LiveMatchRefreshButton` → `AdGate.run` → `LeagueData.pullLiveMatches`/
`refreshStandings`). Free users are correctly gated behind an ad or
subscription per `docs/data-refresh-and-caching.md` ("relaunch must not
silently fetch"). But subscribers (`noAds` and up) already pay to skip the ad
— there's no revenue reason to also make them tap a refresh button. Andrew
wants paid tiers to get their league/team/game data kept fresh automatically,
without changing anything for Free.

This is scoped to **data freshness only**. PWA push (sending picks/predictions
to a linked device) is **out of scope** — it already auto-fires today on
lifecycle events (link mint via `PWARoundPusher.pushSinglePlayerIfNeeded`,
round-open, round-close, declare-winners in `PWARoundPusher.swift`), plus a
manual "Resend to Player App" fallback. This doc only makes sure the
*underlying data* is current when one of those pushes fires.

## Scope decisions (confirmed with Andrew, 2026-08-27)

1. **PWA push** — no change. It's already event/lifecycle-driven, not a
   scheduled job. Nothing to design here.
2. **Email-capture-on-ad-watch** (recovering favourites/settings on a new
   device) — **deferred entirely**, out of this design. Separate feature if
   ever picked up.
3. **Tier cadence** — all League tiers (`leagues3`/`leagues5`/`leagues7`) get
   **one shared cadence**. No scaling by league count. `noAds` is excluded
   (see below) since it has no leagues beyond the free-tier default to keep
   fresh in a way that matters — actually: **open question, see below**.

Wait — `noAds` does have 1 league allowance and real games running, same as
Free. Auto-refresh benefit isn't inherently tied to *league count*, it's tied
to *not showing ads* (`removesAds`). Treating this as **any tier where
`removesAds == true`** (i.e. `noAds` and all three league tiers) is the
correct boundary, not "League tier" specifically — Free is the only tier that
stays exactly as today.

## What triggers a refresh

Two triggers, both **client-only, foreground-only** (no `BGTaskScheduler`,
none exists in the app today — confirmed via grep):

1. **App foreground** — `scenePhase == .active`. There was a foreground hook
   here before (`RootTabView.swift:27,106-108`, commented out 2026-06-15 when
   the interstitial-ad trigger was dropped) — that's the wire-up point to
   reuse, not a new mechanism.
2. **Opening the "Open Round" screen** (`OpenRoundView`/`OpenRoundViewV2`,
   `KillerOpenRoundView(V2)`) — `.onAppear`.

Both call the same helper (proposed `SyncScheduler.refreshIfDue(for:)`) so the
policy lives in one place.

## Gating (who gets it)

```
Entitlements.shared.tier.removesAds == true   // noAds, leagues3/5/7
```

Free stays exactly as today: manual pull via `LiveMatchRefreshButton`, gated
behind `AdGate.run`. This is an *additional* automatic path for paying tiers,
not a replacement for the manual button — subscribers keep the manual
refresh too (instant, no ad, per existing `AdGate` behavior), for the case
where they want to force a check between auto-refresh windows.

**Decided, 2026-08-30 — `noAds` vs league tiers are not identical.**
`removesAds` still gates the *relaxed* auto-refresh ladder (120s matches /
30min standings / 12h ceiling) for both `noAds` and `leagues3/5/7` — but the
**10-min live-match tight-poll loop below is `leagues3/5/7` only**. `noAds`
pays the least of the paid tiers and doesn't fund the per-minute cost of live
polling; league tiers do. `SyncScheduler` needs a second, narrower gate
(`Entitlements.shared.tier` is one of `.leagues3/.leagues5/.leagues7`) for
just the live loop, on top of the existing `removesAds` gate for everything
else.

**Free tier gets none of this, ever, no exceptions.** Confirmed 2026-08-30:
ad-supported must always route through the interstitial (`AdGate.run`)
before any Worker call — this is how Free funds its own CF cost. This also
resolves the 12h-ceiling open question below: it does **not** extend to
Free ungated. See "12h staleness ceiling" section.

## Active window definition (added 2026-08-30, supersedes earlier "4h" heuristic)

Every place below that needs to decide "is a fixture live right now" uses
this one rule — replacing the earlier flat "kickoff in the last 4h" guess
with something anchored to how a match actually runs:

- **Entry test** — a fixture becomes a polling candidate when `now` falls
  within **kickoff − 30 min to kickoff + 60 min**. Only one fixture needs to
  match, out of the round's full selected set across LMS/Predictor/Killer —
  doesn't matter which game, any one hit is enough to trigger the loop for
  the whole round.
  - The −30 min lead catches pre-kickoff delays/warm-up so the loop is
    already running the moment a match actually starts.
  - The +60 min figure is a *normal-case* marker (a match an hour old is
    unambiguously live), not a hard cutoff.
- **Continuation test** — once a fixture is being polled, it keeps being
  polled every 10 min for as long as its status `!= "FINISHED"`
  (`MatchDTO.isFinished`), regardless of whether elapsed time has passed the
  nominal +60 min mark. This is what makes extra time, stoppage time, or a
  delayed match not get dropped early — the entry window decides *when to
  start looking*, `isFinished` decides *when to stop*.
- **New `CacheTTL` constants**: `liveWindowLead` (30 min, pre-kickoff) and
  `liveWindowNominal` (60 min, post-kickoff) for the entry test. No constant
  needed for the continuation test — it's just `!isFinished`, already
  available on `MatchDTO`.

This single definition replaces the ad hoc "kickoff ≤4h ago and
`!isFinished`" phrasing used in earlier drafts of the sections below —
tighter (doesn't start polling 4 hours early) and correct at the tail (never
stops early on a delayed match, which a flat window could do).

**Timezone: confirmed safe by construction, no work needed.** The upstream
football-data source supplies kickoff times in UTC (confirmed 2026-08-30).
`FixtureFormat.kickoffDate` (`FixtureViews.swift:5`) parses this with
`ISO8601DateFormatter()` into a Swift `Date` — an absolute instant with no
timezone attached — so every comparison in this doc (`now` vs.
`kickoff ± window`) is correct regardless of device locale or which
country's competition the fixture belongs to, with no conversion step
needed. Display already localizes automatically too: `FixtureLabel` renders
via `Text(kickoff, format: .dateTime...)`, which SwiftUI formats in the
device's current timezone by default — a UK phone already shows UK local
time today, nothing to build for the Europe rollout on either the
scheduling or display side.

## Cadence

Reuses the existing local-TTL cache machinery in `LeagueDataCache.swift`
(`CacheTTL`, `isFresh`) rather than inventing a second staleness model:

- **Relaxed window**: standard `CacheTTL.matches` (120s) /
  `CacheTTL.standings` (30 min) — i.e. `SyncScheduler.refreshIfDue` just calls
  `pullLiveMatches`/`refreshStandings` unconditionally; the existing TTL
  check inside `LeagueData.load`/cache read already no-ops if still fresh.
  No new "relaxed" constant needed — this **is** the relaxed cadence.
- **Tightened window (10 min)**: only relevant to `standings`, which
  otherwise sits at 30 min — matches move fast during live play so
  `CacheTTL.matches` (120s) is already tight enough. Add a
  `CacheTTL.standingsLiveWindow` (10 min) used **instead of** the 30-min
  standings TTL when any fixture in the held Matches cache is inside the
  active window (see "Active window definition" above).

This mirrors the existing "different threshold for a different job" pattern
already used for `autoAssignTableStale` (1h) vs. `standings` (30 min) in
`CacheTTL`.

## What refreshes

- **League data**: `LeagueData.pullLiveMatches(for:)` +
  `LeagueData.refreshStandings(for:)` (`Cloud/LeagueData.swift:144,184`) —
  both already cache-writing, no UI dependency, safe to call from a
  non-interactive trigger.
- **Team data**: no change — 7-day TTL, seasonal, not worth foreground-polling.
- **Game sync** (PWA cloud state) — reads only; no push triggered here (see
  Scope decisions above).

## Implementation sketch (not yet built)

New `SyncScheduler` (proposed location: `Cloud/SyncScheduler.swift`):

```swift
enum SyncScheduler {
    @MainActor
    static func refreshIfDue(leagues: [LeagueOption], entitlements: Entitlements) async {
        guard entitlements.tier.removesAds else { return }  // Free: no change
        // fire-and-forget; existing TTL checks inside pullLiveMatches/
        // refreshStandings make repeated calls cheap no-ops when still fresh
        _ = try? await LeagueData.pullLiveMatches(for: /* each enabled league */)
        await LeagueData.refreshStandings(for: leagues)
    }
}
```

Wire-up points:
- `RootTabView.swift` — restore the commented-out `.onChange(of: scenePhase)`
  block (lines 27, 106-108), replacing the dropped interstitial call with
  `SyncScheduler.refreshIfDue`.
- `OpenRoundView(V2).swift` / `KillerOpenRoundView(V2).swift` — `.onAppear`.

No new caching layer, no new TTL constants beyond one
`standingsLiveWindow`, no background modes, no server changes.

## Touch-point matrix (for timing review)

Rows are the two triggers × four resources. Columns are the three effective
policy buckets — `noAds` and all League tiers behave identically per the
`removesAds` boundary confirmed above, so they're one column.

| Trigger | Resource | Free | Paid (`noAds` / `leagues3` / `leagues5` / `leagues7`) |
|---|---|---|---|
| **App foreground** (`scenePhase == .active`) | Matches/Scores | No fetch — last cache shown | Fetch if `CacheTTL.matches` (120s) elapsed since last fetch (relaxed); no-op otherwise |
| **App foreground** | Standings | No fetch | Fetch if elapsed since last fetch exceeds: **10 min** if any held match is inside the active window (see definition above); else **30 min** (`CacheTTL.standings`) |
| **App foreground** | Teams | No fetch (functional/free already, 7-day TTL, no change) | Same — 7-day TTL, not part of this change |
| **App foreground** | Fixtures | No fetch (functional/free already) | Same — co-warmed by the Matches fetch above (`/matches` upstream feeds both), no separate trigger |
| **Open Round screen** (`.onAppear`) | Matches/Scores | No fetch — manual button only | Fetch if `CacheTTL.matches` (120s) elapsed (same rule as foreground — screen-open is just a second call site) |
| **Open Round screen** | Standings | No fetch | Same 10 min / 30 min rule as foreground |
| **Open Round screen** | Teams | No fetch | No change (7-day TTL) |
| **Open Round screen** | Fixtures | No fetch | Co-warmed as above |
| **Manual refresh button** (`LiveMatchRefreshButton`) | Matches/Scores | Ad-gated (`AdGate.run`), then fetch subject to Rule A (120s TTL = no-op) | Instant (no ad), same Rule A — **unchanged, kept as a manual override between auto-refresh windows** |
| **Manual refresh** | Standings | Ad-gated | Instant — unchanged |

Notes on timing:
- The 120s / 30min / 10min / 30min-lead / 60min-nominal / 7-day numbers are
  all **existing or proposed `CacheTTL` constants** — nothing here is a new
  polling loop; each
  trigger just calls the existing fetch functions, which already no-op inside
  their TTL. So worst-case call frequency is bounded by how often the user
  foregrounds the app or opens Open Round, not a timer.
- The "10 min tightened standings" only ever fires narrower than the default
  30 min — it never fires *wider*. If no fixture is live, paid tiers still
  get the relaxed 30 min standings cadence.
- Free's row never changes in this design — included in the matrix only so
  the contrast against Paid is visible in one place.

## Live-match tight polling (added 2026-08-30)

The 10-min tightened `standings` TTL above only fires when *something else*
(foreground, screen-open) happens to trigger a check — there's no loop, so a
user sitting on a screen with a live match wouldn't get a mid-session update
without foregrounding again. To cover "kickoff at 15:00, keep syncing every
10 min until FT" while actually watching the app:

- **Superseded 2026-08-30: this loop now lives on the Home screen only**,
  not `OpenRoundViewV2`/`KillerOpenRoundViewV2` — see "Home results-in
  widget" below. Left here for the mechanism detail (the `.task` pattern
  still applies), but the host view changed.
- While a V2 screen that surfaces live-match state is visible
  (originally scoped to `OpenRoundViewV2`, `KillerOpenRoundViewV2`, and any
  V2 Fixtures/Scores screen — now Home only, see above) **and** any fixture
  in `round.fixtureIds` (`Core/Models/Round.swift:10` — mode-agnostic, same
  field for LMS/Predictor/Killer, see "Home results-in widget" for how this
  resolved) is inside the active window (see "Active window definition"
  above — doesn't matter which game), run an in-view polling loop using the
  `.task`
  modifier (not a bare `Task { }` inside `.onAppear` — only `.task` ties the
  task's lifetime to view identity and gets structured cancellation on
  disappear):
  ```swift
  .task {
      while !Task.isCancelled {
          if scenePhase == .active {
              await SyncScheduler.refreshIfDue(...)
          }
          try? await Task.sleep(for: .seconds(600))
      }
  }
  ```
  The explicit `scenePhase == .active` guard is required in addition to
  `.task` — `.task` cancellation covers the view *disappearing*, not the app
  *backgrounding* (the view doesn't disappear when the app backgrounds), so
  without the guard the loop would keep firing while backgrounded, which
  breaks the foreground-only decision.
- The loop is **screen-lifetime only**: `.task` cancels it the moment the
  view disappears, and it re-establishes itself on the next appearance. Combined
  with the `scenePhase` guard above, nothing fires while the app is closed,
  backgrounded, or the screen isn't visible.
- **Gated to `leagues3/5/7` only** (not the broader `removesAds` gate used
  elsewhere in this doc) — see "Decided, 2026-08-30" note above. `noAds` gets
  the relaxed ladder (120s/30min/12h) via foreground + V2 `.onAppear`, same as
  league tiers, but never enters this tighter loop.
- Exit condition: per the continuation test in "Active window definition"
  above, the loop's next iteration naturally stops tightening once every
  tracked fixture is `isFinished` — no fixtures left in the active-window
  set — so it falls back to the relaxed 30-min standings cadence rather than
  needing an explicit "stop polling" signal.
- Cost bound: worst case one `leagues3/5/7` user watching one live match
  generates 6 standings calls/hour for the roughly 90 min–2h the match is
  actually live (bounded by the continuation test, not a fixed window) —
  same shape as the existing 10-min tightened-TTL rule, just now actually
  reached via a loop instead of only via incidental re-triggers.

## 12h staleness ceiling — paid tiers, outer bound of the cadence ladder (added 2026-08-30)

This is the **outer bound of the same `removesAds`-gated cadence ladder**
above, not a new gate: 120s (matches, live) → 10min (standings, live-match
window) → 30min (standings, relaxed) → **12h hard floor**. If held league
data (matches/fixtures or standings) is older than
`CacheTTL.fixturesCourtesyAge` (already defined, 12h,
`LeagueDataCache.swift:34`) when a V2 screen appears or the app foregrounds,
`SyncScheduler.refreshIfDue` treats it the same as any other TTL breach and
refreshes — same `removesAds` gate as everything else in this doc, no change
to Free's behavior.

- Reuses `CacheTTL.fixturesCourtesyAge` (12h) as the outer TTL for both
  matches/fixtures and standings — no new constant needed, and no new
  branch: it's just the least-fresh rung on the existing ladder.
- Free is unaffected: it keeps today's behavior (`fixturesCourtesyAge` still
  only offers a courtesy nudge on the Fixtures view, gated behind the normal
  ad flow) — this section does **not** extend auto-refresh to Free.
- **Resolved, 2026-08-30 (was an open question): no, this does not extend to
  Free ungated.** Ad-supported must always route through `AdGate.run` before
  any Worker call, full stop — that's how Free funds its own CF cost, and
  the "relaunch must not silently fetch" constraint in
  `docs/data-refresh-and-caching.md` stays intact for Free with no
  exceptions. The 12h ceiling only ever shortens the wait *inside* the
  already-`removesAds`-gated ladder; Free's manual, ad-gated path is
  unchanged.

## PWA auto-generation on subscribe — CANCELLED (2026-08-30)

**Cancelled.** Andrew called this off after the design was written but
before any implementation — nothing below was built (no changes to
`Entitlements.apply(tier:)` or the mint call sites). Left in place, struck
through in spirit rather than deleted, so the reasoning isn't lost if this
gets reconsidered later. PWA link mint/revoke stays 100% manual (button
taps on `PlayerDetailViewV2`/`PlayersView`), same as it was before this doc
existed.

Original proposal, for reference: Today PWA link mint/revoke is 100% manual
(button taps on `PlayerDetailViewV2`/`PlayersView`, per the audit). Proposal: for
`leagues3/5/7` only (matches existing `pwaAccess == .full` gating in
`Entitlements.swift` — no entitlement change needed, just automating an
already-permitted action), auto-mint a PWA link the moment it becomes
possible:

- **New player added while already on a league tier** — mint immediately
  instead of requiring the manual "Generate Link" tap. Same
  `SubmissionsClient.mintLink` call as today, just moved from
  button-tap-triggered to player-creation-triggered.
- **Upgrade to a league tier with existing players** — sweep existing
  players lacking a link and mint one each. **Resolved 2026-08-30: the hook
  already exists**, no new mechanism needed —
  `Entitlements.apply(tier:)` (`Entitlements.swift:168`) is called by
  `PurchaseService` on every launch/purchase/restore and already
  fire-and-forgets a `Task` gated on `canUseCloud` (line 185, used today to
  default `pwaSubmissionsEnabled`). The mint sweep slots into that same
  `Task`. Since `apply` runs on *every* resolution, not just genuine
  upgrades, the sweep must be idempotent — but "mint only for players
  lacking a link" already is, by construction, so no extra guard needed.
- Manual mint/revoke/rename UI stays as-is for the actual link-management
  cases (regenerate, rename, explicit revoke) — this only removes the
  "remember to tap generate" step for the common case.
- Cost: one Worker call per player, only for already-paying league-tier
  users, only once per player (not recurring) — negligible against the
  auto-refresh cadence above.

## PWA links on downgrade (added 2026-08-30)

**Decided 2026-08-30: leave links live, stop pushing data.** On downgrade
from a league tier to `noAds`/`free` (lapse, cancellation, billing failure),
existing PWA links are **not** auto-revoked. Rationale: a hard auto-revoke
punishes accidental/billing-hiccup lapses immediately; leaving links live
but simply no longer receiving `PWARoundPusher` updates (since pushing is
already gated the same way sync is, via `removesAds`/`pwaAccess`) is a
softer landing. Truly abandoned links age out via the existing planned
90-day orphaned-data cleanup job (`worker-api-orphaned-data-cleanup`
memory) rather than a new immediate-revoke path — no new mechanism needed,
just confirms the existing cleanup job is the intended backstop for this
case too.

## Per-game results-in indicator — IMPLEMENTED, per-game not a Home widget (2026-08-30)

**Reworked 2026-08-30**, after Andrew clarified this needs to live on each
individual game, not as a dedicated Home-screen widget — the aggregated
"LMS: 3/10 in, Predictor: 5/8 in" surface originally designed below was
never built; this section now describes what actually shipped instead.

**Turned out to already exist.** `NextUpStep.matchesInProgress(finished:
total:)` (`NextUpStep.swift:100`) and its rendering as "Matches playing — X
of Y in" on `GameSummaryRow` (`GameSummaryRow.swift:161`, shown on the
Games portal list and reused by Home's Favourites cards) already were this
indicator, per-game, already in production — nothing needed inventing. The
only real gap: `GameSummaryRow` read the local Matches cache **once** per
round (`.task(id: roundContext.currentRound?.id)`,
`GameSummaryRow.swift:105`, guarded to only fire once the round's past its
deadline) and never re-read it, so the count sat frozen even once
`SyncScheduler` started refreshing that same cache in the background.

**Fix implemented**: `GameSummaryRow.swift:105-119` — the one-shot cache
read became a loop that re-reads `LeagueData.load(for: game.leagues)`
(cache-only, no network — `SyncScheduler` from Home is what actually
fetches) every 60s while `NextUpStep` resolves to `.confirmEntries` (deadline
passed, kickoff hasn't) or `.matchesInProgress` (live), and stops the moment
it resolves to anything else (`.processResults`, etc.) since there's nothing
left for a re-read to change. Continuing through `.confirmEntries` (not
just `.matchesInProgress`) matters — the task's identity is
`roundContext.currentRound?.id`, which doesn't change again until the round
closes, so stopping the loop before kickoff would mean the row never
noticed once matches actually went live.

No new Worker/D1 work (confirmed with the same reasoning as the original
"why do we need CF-side work" correction below) — this is purely a local
cache re-read wired up to data `SyncScheduler` already fetches elsewhere.

**Not built**: the aggregated Home-level counter and the "portal push on
result change" idea from the original design below were both descoped
along with moving this to per-game — `PWARoundPusher` still only fires on
its existing lifecycle events, unchanged.

---

*Below is the original Home-widget design, kept for the reasoning it
contains (particularly the "no CF-side work needed" correction and the
per-mode fixture-model research), superseded by the per-game
implementation above.*

**Mechanism — entirely client-side, no new Worker route (corrected
2026-08-30; see below for what changed).**

Initial version of this section proposed a new `results-status` Worker
endpoint doing a D1 join. That was unnecessary complexity — corrected after
Andrew asked "why do we need CF-side work" and the honest answer was: we
don't. Two facts make this pure client arithmetic:

- The client already **holds the round's relevant fixtures locally** — a
  game's picks/survivors/predictions are on-device data (the same data
  already pushed to the portal). No join needed; there's nothing to join
  *across* — it's one manager's own game against a match list they already
  fetched.
- The client already **fetches match status** via the existing
  ladder/live-loop calls (`pullLiveMatches`) — `MatchDTO.isFinished` is
  already in that response.

**Resolved 2026-08-30 — "relevant fixtures per mode" needs no per-mode
design, and the join already exists:**

- All three modes already share one schema: `Round.fixtureIds: [Int]`
  (`Core/Models/Round.swift:10`). LMS doesn't need a "team pick → fixture"
  join designed for it — the round already stores fixture IDs directly,
  mode-agnostically, same as Predictor and Killer (`Game.modeRaw` is the
  only thing that varies).
- The exact "X/N finished" computation this widget needs is **already
  built and already in production**: `RoundPhase.make(for:data:)`
  (`NextUpStep.swift:47-75`) filters the held Matches cache to
  `round.fixtureIds`, counts `isFinished || isPostponedOrCancelled`, and
  returns `.live(finished:total:)` — this already drives the existing
  "Next Up" nudge/badge on the games list today.
- **So the widget and the live-poll trigger both build on `RoundPhase.make`
  rather than reimplementing the join** — reusing production code instead
  of writing a parallel one, and guaranteeing the widget's count can never
  drift from what the Next-Up badge already shows for the same round.
- One real gap: `RoundPhase.make` is per-`Game`, single-round. The Home
  widget wants this aggregated per mode across a manager's multiple active
  games (e.g. "LMS: 3/10", "Predictor: 5/8") — that's a thin wrapper (group
  active games by mode, call `RoundPhase.make` per game, sum), not a new
  computation.

So the actual mechanism:

- Home `.onAppear` and app foreground (for `leagues3/5/7`, same gating as
  the live-poll loop) call the **existing** `LeagueData.pullLiveMatches`/
  `refreshStandings` — same calls the relaxed ladder already makes, nothing
  new.
- The widget count is computed **locally**, via the per-mode aggregation
  over `RoundPhase.make` described above — not a hand-rolled filter.
- **Portal push on result change** — also client-side, reusing the existing
  `PWARoundPusher` mechanism (already used for round-open/close/declare-
  winners): after a ladder/live-loop fetch, if the locally-computed
  finished-fixture set changed since the last check, call the same push
  function client-side. This is one more trigger point for a push mechanism
  that already exists, not new infrastructure — linked devices only get
  updated when the manager's own phone made the call, consistent with the
  Core principle (no server-autonomous push).
- While Home is visible and the round has a live-window fixture, reuse the
  existing 10-min `.task` loop (see "Live-match tight polling" above) —
  this **replaces** the Open-Round-screen loop per the 2026-08-30 "Home
  only" decision; Open Round screens fall back to the relaxed ladder.
- Free/`noAds`: no change for now (rollout order above).

**No new build surface beyond the rest of this doc** — no Worker route, no
D1 query, no server-side push trigger. Just: reuse existing fetch calls,
add local filtering/counting, add one more client-side call site into the
existing `PWARoundPusher`.

## Home sync indicator — DESCOPED (2026-08-30)

**Descoped.** Andrew pulled both the spinner and the "next sync in X"
countdown after the design below was written; neither was implemented —
`SyncScheduler.isSyncing` exists (it's harmless, cheap published state) but
nothing in the UI binds to it. `SyncScheduler` itself, the auto-refresh it
performs, and the live-poll loop are unaffected — this only removes the
*visible indicator* of that activity, not the sync behavior itself. Kept
below for reference in case this gets revisited.

Original proposal, for reference: a small UI element on the Home screen so
syncing isn't invisible: an icon that spins while a sync is in flight, plus
a "next sync in X" countdown —
**but the countdown only appears in the one state where it's actually
true.**

- **Spinner** — reflects real in-flight network activity, full stop. New
  published state (`SyncScheduler.isSyncing: Bool` or equivalent), set
  `true` around any `pullLiveMatches`/`refreshStandings` call regardless of
  trigger (foreground, Home `.onAppear`, the live-poll loop, or the manual
  refresh button), `false` on completion. Home binds a rotation animation to
  it. No new sync mechanism — purely an observability layer over calls this
  doc already makes.
- **"Next sync in X" countdown** — **shown only while the Home live-poll
  loop (see "Live-match tight polling") is actually running**, i.e. a
  `leagues3/5/7` user with a fixture inside the active window. That's the
  one state with a real scheduled next call (`lastPollAt + 10min`), so it's
  the only state honest to display a ticking countdown for.
- **Every other state — no countdown text**, confirmed 2026-08-30 (dropped
  after flagging that a countdown outside the live loop would imply a
  background scheduler that doesn't exist, since this design is
  foreground-only). Idle/relaxed-ladder states just show the icon at rest;
  spinner still fires normally on any real fetch, just no "next in" text
  attached to it.
- ~~This resolves the earlier "should `refreshIfDue` be silent" open item~~
  — **superseded by the descope above**: with no indicator built, the
  answer reverts to yes, silent — there's no spinner to make it otherwise.

## Open items before build

- ~~Confirm the `noAds`-vs-League-tier boundary~~ — **resolved 2026-08-30**:
  relaxed ladder is `removesAds`-gated (noAds + league tiers), live-poll loop
  is `leagues3/5/7`-only. See "Decided, 2026-08-30" note under Gating.
- ~~Decide whether `refreshIfDue` should be silent~~ — **moot, 2026-08-30**:
  the Home sync indicator that would have made this a real question was
  descoped — with no spinner built, it's silent by default. See "Home sync
  indicator."
- ~~Confirm which V2 screen(s)... should host the live-match polling
  loop~~ — **resolved 2026-08-30**: Home screen only (V2 Home), not Open
  Round screens. **Implemented** — see `V2PreviewMenuView.swift` `.task`.
- ~~Entitlement/tier-change hook for the PWA sweep~~ — **moot, 2026-08-30**:
  the auto-mint-on-subscribe feature this hook was for got cancelled before
  build. See "PWA auto-generation on subscribe."
- Email capture / cross-device PWA-link recovery stays fully deferred as a
  separate feature (per original scope decision) — not designed further
  here even though 2026-08-30 discussion confirmed it's league-tier-only in
  concept; the recovery flow itself is still unbuilt and unscoped.
- ~~Worker endpoint / D1 join for results-status~~ — **removed 2026-08-30**:
  no CF-side work needed, corrected to pure client-side computation (see
  "Home results-in widget" mechanism). Kept as a struck-through line so the
  reasoning isn't lost if this gets revisited.
- ~~Identify what "the round's relevant fixtures" means per mode~~ —
  **resolved 2026-08-30**: no per-mode distinction needed. All three modes
  share `Round.fixtureIds: [Int]`, and the "X/N finished" computation
  already exists in production (`RoundPhase.make`, `NextUpStep.swift:47`).
  See "Home results-in widget." Remaining thin gap: a per-mode aggregation
  wrapper across a manager's multiple active games (group by mode, sum
  `RoundPhase.make` per game) — not a new join, just a wrapper, so not
  tracked as a separate open item.
