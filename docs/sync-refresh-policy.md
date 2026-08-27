# Auto-refresh policy for subscribers (foreground + Open Round)

Status: **draft design, not yet implemented** (2026-08-27).

## Problem

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
  standings TTL when any fixture in the held Matches cache kicked off in the
  last 4 hours and `!isFinished` (`MatchDTO.isFinished`, `DTOs.swift:54`).

  Concretely: `SyncScheduler` checks the held `LeagueDataCache.Matches`
  snapshot for `kickoff` within the last 4h and `status != "FINISHED"`; if
  found, pass the tightened TTL into the standings freshness check instead of
  the default.

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
| **App foreground** | Standings | No fetch | Fetch if elapsed since last fetch exceeds: **10 min** if any held match kicked off ≤4h ago and `!isFinished`; else **30 min** (`CacheTTL.standings`) |
| **App foreground** | Teams | No fetch (functional/free already, 7-day TTL, no change) | Same — 7-day TTL, not part of this change |
| **App foreground** | Fixtures | No fetch (functional/free already) | Same — co-warmed by the Matches fetch above (`/matches` upstream feeds both), no separate trigger |
| **Open Round screen** (`.onAppear`) | Matches/Scores | No fetch — manual button only | Fetch if `CacheTTL.matches` (120s) elapsed (same rule as foreground — screen-open is just a second call site) |
| **Open Round screen** | Standings | No fetch | Same 10 min / 30 min rule as foreground |
| **Open Round screen** | Teams | No fetch | No change (7-day TTL) |
| **Open Round screen** | Fixtures | No fetch | Co-warmed as above |
| **Manual refresh button** (`LiveMatchRefreshButton`) | Matches/Scores | Ad-gated (`AdGate.run`), then fetch subject to Rule A (120s TTL = no-op) | Instant (no ad), same Rule A — **unchanged, kept as a manual override between auto-refresh windows** |
| **Manual refresh** | Standings | Ad-gated | Instant — unchanged |

Notes on timing:
- The 120s / 30min / 10min / 4h / 7-day numbers are all **existing or
  proposed `CacheTTL` constants** — nothing here is a new polling loop; each
  trigger just calls the existing fetch functions, which already no-op inside
  their TTL. So worst-case call frequency is bounded by how often the user
  foregrounds the app or opens Open Round, not a timer.
- The "10 min tightened standings" only ever fires narrower than the default
  30 min — it never fires *wider*. If no fixture is live, paid tiers still
  get the relaxed 30 min standings cadence.
- Free's row never changes in this design — included in the matrix only so
  the contrast against Paid is visible in one place.

## Open items before build

- Confirm the `noAds`-vs-League-tier boundary above (this doc assumes
  "any `removesAds` tier", not "League tier only" — flag if that's wrong).
- Decide whether `refreshIfDue` should be silent (no loading UI, since it's
  incidental to opening a screen the user already wanted) — assumed yes.
