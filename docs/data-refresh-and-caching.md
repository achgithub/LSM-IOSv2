# Data refresh & caching architecture

Status: **agreed design, not yet implemented** (2026-06-17). Picks up tomorrow.

This describes how sports data (scores, league table, fixtures, teams) is fetched,
cached and gated. The whole thing rests on **two independent layers** that must
never be conflated.

---

## Layer 1 — the App (protects revenue)

Governs **when the app is allowed to request fresh data**.

- The app may fetch an update **only** if the user is **subscribed** or has
  **watched a rewarded ad**.
- **Single exception: first install** — the initial load is free (you can't show
  a blank, ad-walled first run). **Period.**
- Relaunch / reopen / tab-switch must **not** silently fetch. The app shows the
  **last data it persisted locally** and only goes to the network on a sub/ad-gated
  action.
- Applies to the freshness *product*: **Scores** and the **League table**.

Implication: the app keeps a **local persisted cache** per resource (with a
timestamp) so it can show last-known data offline / on relaunch without a call.

## Layer 2 — the Worker (minimises cost)

Governs **when the Worker calls the upstream football-data API**.

- Cloudflare proxies everything. Many app requests are fine — they're served from
  the Worker's **cache / D1**. Upstream is hit **at most once per TTL window per
  resource**, shared across all users.
- **D1 reads/writes are cheap and acceptable.** The scarce resource is **upstream
  API quota**, controlled by TTLs.
- A fetch triggered for *any* reason refreshes the data **and its timestamp**, so a
  later request within the TTL is served from cache — no upstream call.

## The divorce (the key point)

Worker-freshness ≠ App-freshness. The Worker may hold 1-min-fresh scores, but a
free user only *receives* them when they watch an ad. **The user never gets the
Worker's freshness for free** (except first install). "One upstream call refreshes
several sections" is fine for D1/cost, but the app still gates what the *user* gets.

---

## Per-resource rules

| Resource | Upstream source | App gate | Worker TTL |
|---|---|---|---|
| **Scores** | `/matches` | **Gated** (Scores-tab refresh) | **1 min** |
| **Fixtures** | `/matches` | **Functional / free** (schedule; fetched at game creation / open round) | **4 hours** |
| **League table** | `/standings` | **Gated** (Standings-tab refresh + auto-assign) | **30 min** |
| **Teams** | `/teams` | Functional / free | Static — long TTL / seasonal sync |

### Cross-resource warming
- `/matches` upstream → refreshes **Scores (1 min) + Fixtures (4 h)** together (same
  source). So a scores refresh warms the fixtures cache.
- `/standings` upstream → refreshes the **table (30 min)** on its own. A scores
  refresh does **not** warm the table.

---

## Auto-assign table-freshness rule

Auto-assign picks the **bottom-of-table available team**, so it's only as correct
as the table it works from.

- On Auto-Assign, check the **age of the league table the app holds**.
- If **> 1 hour old** → prompt: *"The league table is over an hour old — fetch the
  latest?"*
  - **Yes** → **ad-gated** (free watches an ad; subscriber instant) → fetch fresh
    standings → auto-assign against the up-to-date table.
  - **No / cancel** → **proceed with the stale table** (manager's call — decline
    behaviour = option 1).
- If **≤ 1 hour old** → auto-assign runs with held data, no prompt, no fetch.

The **1-hour app-side staleness threshold** is deliberately separate from the
Worker's **30-min upstream TTL** — different jobs.

---

## Worked examples (both confirmed)

**1. Warm cache from an active subscriber.** A subscriber keeps refreshing scores →
each expired-TTL refresh makes one upstream `/matches` call, warming scores +
fixtures. A free user then creates a game → fixtures served from the warm cache →
**zero upstream calls**. If the subscriber is active 24/7, the free user never
triggers an upstream call.

**2. Thundering herd, deduped.** 5 min after full-time the scores cache is stale.
A free user hits refresh (watching an ad) 10 s early → one upstream call refreshes
the cache. 30 others refresh 10 s later (each subscribed or having watched their own
ad) → all served from cache. Net: **31 gated user-refreshes, 1 upstream call.**

---

## Local TTLs (Layer-1 cost shield, agreed + shipped)

Every resource now has a **local cache + local TTL**. Inside the TTL the app
answers from its own on-disk cache and never calls the Worker, so exploring the
app can't generate wasteful Worker traffic. Values (in `CacheTTL`):

| Resource | Local TTL |
|---|---|
| Scores | 60 s |
| Standings | 30 min |
| Fixtures | 4 h |
| Teams | 7 days |
| *Auto-assign staleness* | 1 h (separate threshold — when to *prompt*, not when to call) |

**Rule A (locked):** an explicit refresh while the cache is still within its TTL
serves the cache — **no ad, no Worker call** (nothing fresher exists to fetch).

**Important — these are hardcoded Swift constants, not runtime config.** Changing
a value needs a code edit + App Store release. They are the baked-in defaults /
offline fallback. True post-launch tuning *without* a release = remote config
(serve TTLs from the Worker) — deferred to the Worker pass (see below).

## Cache corruption (handled)

Local cache files can corrupt (partial write, or schema drift from an older app
version). `LeagueDataCache.read` health-checks every read: a file that exists but
won't decode is **deleted on the spot** and reported as `.corrupt`. Recovery is a
**free** fetch — the user never watches an ad to recover from our own bad data.
Empty/missing = normal first-run miss → free first fill.

## Current state vs target

**Done — client cache + local-TTL pass (this session, on top of `7e304d3`):**
- All four resources cache-first with local TTLs above. New `LeagueDataCache.Fixtures`
  + `Teams` snapshots; `FixtureDTO` made `Codable`.
- **Table back door closed:** `LeagueData` now reads standings from cache only
  (free first fill if empty/corrupt); fixtures/teams refresh only past their TTL.
  Opening Picks/Results/Open-Round is no longer a free table refresh.
- **Auto-assign staleness prompt** in `PicksEntryView`: table > 1 h old → offer a
  gated refresh (`refreshStandings` behind `AdGate`); decline → assign on held table.
- **Rule A** on the Scores/Standings refresh buttons (fresh-within-TTL = no-op,
  no ad); corruption recovery is a free fetch.
- `ResultsEntryView` "pull from server" uses `forceFixtures: true` (the ad buys
  genuinely fresh results, bypassing the fixtures TTL).

**Done earlier (shipped, commit `7e304d3`):**
- App-side Scores & Standings cache-first + ad-gated refresh + per-league cache.

**To do — Worker pass (next):**
- **Worker:** give `/standings` (30 min) and `/fixtures` (4 h) the same
  request-triggered TTL + shared-cache pattern that `/scores` already has. Set
  `/scores` TTL to **1 min**. Confirm `/matches` upstream writes both scores +
  fixtures caches/timestamps. Reconcile the existing nightly cron vs request-TTL.
- **Remote config (option C):** serve the per-resource TTLs from the Worker so they
  can be retuned from real usage **without an app release**; `CacheTTL` constants
  become the offline fallback.

**Open / not yet decided:**
- Exact reconciliation of the Worker's existing cron warm vs the request-triggered
  TTLs.
