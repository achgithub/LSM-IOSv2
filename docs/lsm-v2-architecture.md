# LSM v2 architecture sketch

Status: **scaffolded; feature design locked, build not started** (updated
2026-06-24). The repo, iOS rename/reorg, and the cloud *read* path (regional
shards live, app repointed) are done — see `V2-SCAFFOLD.md` / `worker/MIGRATION.md`.
The Predictor / league-publish / backup / submission-queue feature design is now
settled — see **[§0 Design decisions locked](#0-design-decisions-locked-2026-06-24)**,
which is the binding record; §§1–6 below are the original sketch kept for
rationale, and where they predate §0 they are annotated. v1 (Last Man Standing,
single mode, SwiftData-local) keeps shipping/supported throughout — see
[Repo strategy](#5-repo-strategy-and-v1-support).

LSM = "Last Stand Manager," the app-level brand. v2 adds a second game mode
("Predictor") alongside the existing one (now named "LMS" at the mode level).
Both modes live in one app under one subscription. **Game state stays on-device
(SwiftData); the cloud is deliberately thin** — see §0.

---

## 0. Design decisions locked (2026-06-24)

These supersede anything below them where they conflict (notably the original
"cloud-backed game state / source of truth is D1" framing — that was dropped).

### Build order
1. **Predictor** — fully on-device, no cloud.
2. **Cloud bundle = publish + backup** — one pay-only feature, shared R2 + a
   Worker write-route.
3. **PWA + submission queue** — last; the only piece needing any live
   server-side game state (a transient submission inbox).

### Game model & gameplay
- **Game state stays on-device (SwiftData), same as v1** — LMS *and* Predictor.
  The cloud does NOT hold games/players/picks/predictions. Cloud touches only:
  the transient PWA submission inbox (D1), backup snapshots (R2), and league
  publish snapshots (R2).
- **One `Game` `@Model` + a `mode` discriminator** (`.lms | .predictor`), not a
  sibling model — driven by wanting both an LMS and a Predictor game visible in
  the same home-screen Games list. `GameCard` gets a mode badge; the secondary
  line is mode-aware (LMS "Round N · X active" vs Predictor "Matchday N · X
  players · leader"). New Game opens with a mode picker, then mode-appropriate
  settings.
- **Predictor**: each player predicts a score for every fixture in scope; a new
  `Prediction` model mirrors `Pick`; **scored client-side at round close** (same
  trigger as LMS results entry); fixture/round selection **reuses the LMS
  mechanism**. No elimination.
- **Settings reuse**: implicit "remember last settings" (UserDefaults prefill of
  the New Game form). No named/cross-game templates.

### Predictor scoring — configurable, tiered "best enabled rung"
Each rung is an independent toggle + point value; a prediction earns the **single
highest enabled rung** it qualifies for (disabled rungs are skipped → cascade
down). Defaults:

| Rung | Type | Default |
|---|---|---|
| Exact score | value | 4 |
| Goal difference / margin (draws inherit this — no special-case) | toggle + value | on, 3 |
| Correct result / outcome | toggle + value | on, 2 |
| **Joker** — one double-points fixture per matchday | toggle | off |

The joker, if on, doubles whatever that fixture scored. A correct non-exact draw
necessarily lands on the goal-difference rung (a draw *is* GD 0), so the plain
Result rung is unreachable for draws — accepted intentionally.

### Predictions league
- **Ranking: standard competition ranking by points only** — ties share a
  position ("1, 1, 3"); no secondary point tiebreakers; within a tie, list
  alphabetically.
- Three render targets off one `LeagueStandingsSnapshot` shape: **on-device
  table** (reuse `StandingsView` look), **share-card** (reuse
  `SummaryCardView`/`ImageRenderer`/`ImageSharePresenter`; cap ~top-10; shows
  names — no PIN possible on an image, accepted), and the **published page**.

### Cloud bundle — publish + backup (one pay-only feature)
- **Backup**: explicit, user-triggered **R2 blob snapshot** (serialize game(s) →
  push → restore); doubles as export/import. Sold on durability/continuity
  (survive a phone change / season archive), NOT "free up space" — the data is
  small (worst case ~200 players × full Predictor season ≈ tens of thousands of
  rows ≈ single-digit MB; SwiftData handles it easily).
- **Publish**: the app uploads a **complete self-contained snapshot** to R2 via a
  Worker write-route (app never holds R2 creds): the manager-selected fixtures +
  scores for the recent window, **per-person weekly results**, cumulative league
  standings, and the next matchday's selected fixtures. One Cloudflare **Pages**
  site renders `/l/<unguessable-uuid>` from the blob.
- **Privacy: the ENTIRE published page is PIN-gated and the PIN is required**
  (weekly results are per-person). PIN is validated **server-side** in the Pages
  Function and stored hashed; names are never in the openly-served payload. (Same
  pattern as the darts React-Native app.)
- **No public-page ads** (PIN-gated, internal, near-zero traffic — not worth it).
  Free-tier revenue stays the existing in-app ads around the share-card flow.
- **One paid cloud entitlement gates ALL cloud features** — backup, publish,
  *and* the PWA links + submission queue. Because these are paid, they have **no
  ad gate** (ads are only the free-tier path). Free tier = no cloud, ads on
  share-cards.

### Submission-queue manager UX (ships with the PWA, last)
- Submissions are the one game-related thing in the cloud (PWA writes pending
  rows to D1; app reads them). **Approval writes the real pick/prediction to local
  SwiftData** and marks the cloud submission decided; rejection just marks it
  rejected.
- The queue is **not a free-floating inbox — it's anchored under "This Round"** in
  `GameDetailView.roundSection` (a `.submissions` case on the existing `RoundSheet`
  pattern). A tray icon + total-pending count on the home screen and a per-game
  count on `GameCard` funnel the manager there.
- **Player ↔ link token (data-model change):** minting a player's PWA link adds
  a **separate, revocable `submissionToken: UUID?`** to the on-device `Player`
  (`Core/Models/Player.swift`) — *distinct from* the player's existing local
  primary-key `id` (don't expose that as the public credential; the token must be
  rotatable). The token is what's in the link URL and what the cloud
  `submission_tokens` / `submissions` carry, so an incoming/approved submission
  maps back to the right local `Player`. nil until a link is minted; regenerating
  = new token (old link dies).
- **Mint / regenerate / revoke is in-app** (per-player in the roster —
  `PlayersView`): Cloudflare has no manager UI. "Regenerate" writes a new local
  token *and* calls the Worker to upsert-new + revoke-old in `submission_tokens`,
  so the old link stops validating immediately (pending submissions under it can
  be auto-voided). The phone is the admin console; the Worker/D1 is just the
  token store. **Paid (cloud entitlement) → no ad gate** on sharing.
- **Share produces a pre-formatted, name-personalized message** through the iOS
  share sheet (Messages/WhatsApp) — the link plus install instructions and a
  friendly fallback. Default tone (editable before sending):
  > Hi {playerName}, click this link, then save it as a bookmark or add it to
  > your phone's home screen as an icon: {link}. If you're not sure how, just ask
  > me next time you see me.

  "Add to home screen" is the PWA install — the link behaves like a lightweight
  app once saved.
- Per-player rows with status chips (pending / approved / no-submission);
  **swipe right=approve, left=reject, plus "Approve all pending."** LMS submission
  = one team; Predictor submission = a whole slate (a score per selected fixture).
- **Rolling window**: default view is the current round, but a filter exposes the
  **last N rounds** (read-only history: submission + decision + timestamp) for
  query handling. **One shared "recent window" constant (default 3)** drives both
  the queue history and the published page's recent-results section so they never
  drift; D1 retains that window and prunes older rows.

### Still open
Exact PIN UX; whether free-tier share-card generation is rewarded-ad-gated vs
banner-only; recent-window constant 2 vs 3.

---

## 1. The two modes

### LMS (Last Man Standing)
> **Superseded by §0:** LMS stays **on-device (SwiftData)**, as in v1 — it is
> *not* re-homed to D1. The text below describing a D1 source of truth is
> obsolete.

Existing elimination game. One pick per round per player; wrong (or non-)pick
eliminates; last player standing wins. Round/Pick/Player shape carries over
largely as-is from v1 — see `ios/LSM/LSM/Core/Models/{Game,Round,Pick,Player}.swift`.

### Predictor
New season-long game. Each week, players predict the score of each fixture
in scope. Points awarded per fixture (exact split TBD, working example:
1 pt correct outcome + 1 pt correct home score + 1 pt correct away score).
Points accumulate across the season into a standings table, published the
same way league tables are today. Unlike LMS, players are never eliminated —
they can join/leave mid-season, and the "game" is really a running league
table rather than a knockout.

> **Superseded by §0:** scoring is the configurable tiered model in §0 (not the
> 1+1+1 working example above), and Predictor is **on-device like LMS** — season
> durability comes from the paid R2 backup, not from cloud-backed game state.

---

## 2. LSM Cloud (backend)

A Cloudflare Worker + D1, evolved from the existing read-only sports-data
Worker (`worker/` — currently `teams`, `fixtures`, `standings`,
`attest_devices`, `sync_meta`, all per-league config, no per-user state).

**Leagues + fixtures consolidation (v2-fork only):** v1 runs one D1 database
*per league* (`lms-pl-db`, `lms-bl1-db`, ...), each with its own
`teams`/`fixtures`/`standings` and a static `league.config.json` baked into
the worker bundle — there's no `leagues` table and no `league_id` column on
`fixtures` today, because the database itself is scoped to one league. v2
replaces the per-league-config-file model with a `leagues` table (name,
footballDataCode, TTLs, roundsPerSeason, region, etc. as rows instead of
files) and `league_id` columns on `teams`/`fixtures`/`standings`.
`teams.external_id` and `fixtures.id` are football-data.org's own ids and
are already globally unique across leagues, so no id-renumbering is needed.

**v1 is explicitly left as-is** — its per-league D1s are not migrated, not
touched, and keep running independently. This consolidation only happens in
the v2 fork's own (separate) infrastructure, avoiding any live-migration risk
to v1's production data.

**D1 topology (decided 2026-06-24, evaluated independently of v1's
precedent): regional sharding, not one global D1 and not one D1 per
league.** With ~2000 leagues worldwide a realistic ceiling, all three
options were weighed on their own merits:

- *One D1 per league* (v1's model) doesn't scale to thousands — Workers' D1
  bindings are static, configured at deploy time, so thousands of databases
  means either thousands of hardcoded bindings (unworkable) or falling back
  to D1's HTTP API for any cross-database access (slower, no binding-level
  performance, and a meta-system just to provision/manage that many
  databases).
- *One global D1* loses the maintenance-window benefit entirely — at 2000
  leagues spanning every timezone, it's always live hours *somewhere*, so
  there's no quiet period for migrations, and every write (sync crons,
  submissions, predictions) serializes through one writer queue with global
  blast radius on a bad lock/migration.
- *Regional shards* (UK standalone given Premier League's outsized query
  volume; separate shards for the rest of Europe, North America, South
  America, with more added as needed) hit the sweet spot: bounded blast
  radius per shard, real timezone-aligned maintenance windows (leagues
  within a region cluster around similar match-time hours), a small fixed
  number of static D1 bindings (4-6 to start, trivially expressible in
  wrangler config), and cross-league queries stay single-query for the
  realistic case (a player following leagues within their own region) —
  true cross-region queries are rare enough to eat the fan-out cost.

This adds one piece of real complexity neither extreme needs: something has
to know which shard a given `league_id` lives in before querying it — a
small static manifest (region per league, rarely changes) read once to pick
the right D1 binding. Per-league data is small enough (~20-30 teams, ~380
fixtures/season, ~20-30 standings rows) that this is purely an
isolation/maintenance-window decision, not a row-count one — even a single
global D1 would hold the data fine at 2000 leagues; regional sharding wins
on blast radius and ops, not raw capacity.

v2 adds tables that didn't exist before, because v1 deliberately kept all
game state on-device:

- `games` — id, mode (`lms` | `predictor`), league config, settings (allowRepeats,
  drawEliminates, scoring rules for Predictor, etc.), status.
- `players` — id, game_id, display name, status (active/eliminated for LMS;
  just "active" for Predictor since there's no elimination), join/leave dates.
- `picks` (LMS) — player_id, round_id, team_id, result.
- `predictions` (Predictor) — player_id, fixture_id, predicted_home_score,
  predicted_away_score, points_awarded.
- `submission_tokens` — player_id, uuid token (the player's unique link),
  created_at, revoked_at.
- `submissions` (the approval queue) — token_id, fixture/round context,
  payload (pick or prediction), status (pending/approved/rejected),
  submitted_at, decided_at.

Fixture/team/standings data stays shared and unchanged — both modes consume
the same upstream-sourced sports data the v1 Worker already maintains; the
new tables are purely the per-game/per-player layer v1 never needed.

**Open question:** whether v2's Worker is a new deployment (own D1, own
routes) that *also* pulls fixture data, or whether it reads fixture data
from the existing v1 D1/Worker via a service binding to avoid duplicating
the football-data.org sync logic. Leaning toward the latter (don't fetch the
same upstream data twice), but worth deciding once the v2 repo exists.

---

## 3. Player app (the PWA)

A lightweight shared web app, not tied to either mode specifically:

- Manager generates a unique link per player from inside LSM (mints a
  `submission_tokens` row). No email, no account — just an unguessable UUID,
  chosen specifically to avoid GDPR personal-data handling.
- Opening the link shows the player only what's actionable right now: for
  LMS, the current round's available teams; for Predictor, this week's
  fixtures awaiting a score guess.
- Submitting writes a row into `submissions` with status `pending` — it does
  **not** write directly into `picks`/`predictions`.
- The manager opens LSM, sees the queue, approves or rejects each entry.
  Approval is what actually creates the `pick`/`prediction` row; rejection
  discards it. This is the misuse gate — anyone with the link can submit, but
  nothing is live until the manager confirms it.
- Manager-typed entries (the manager entering a pick/prediction directly,
  on behalf of a player who isn't online) skip the queue entirely and write
  straight through — this is the permanent fallback for players who never
  self-submit, not a stopgap.

---

## 4. Cross-app subscriptions (v1 → v2)

**Decided 2026-06-24, chosen approach: Sign in with Apple as the identity
bridge.** A v1 subscriber shouldn't have to re-pay in v2. Apple doesn't share
subscriptions across different bundle IDs automatically, and RevenueCat's
multi-app entitlement sharing (multiple App Store apps under one RevenueCat
Project, entitlements visible across them) only works if both apps agree the
purchaser is the *same customer* — which requires a stable shared App User
ID. v1 is anonymous today (install-scoped ids), so there's nothing to bridge
on without adding *something*.

Sign in with Apple supplies that bridge without reopening the GDPR-light
design used elsewhere: it returns a stable, opaque per-developer-account
identifier (no real email required, even if the user picks "Hide My Email").
v1 and v2 both authenticate with it, RevenueCat recognizes the same customer
across both apps' entitlements, and the underlying subscription keeps
billing/renewing through whichever app's App Store record it was originally
purchased on — v2 just checks entitlement against the same RevenueCat
customer rather than requiring its own purchase.

Caveats accepted: (1) this is low-priority unless v1 actually gets enough
subscribers for it to matter — explicitly *not* blocking v2's build; (2) the
Apple-id-to-customer link can break if the user revokes app access from
their Apple ID settings or the developer Team ID changes — rare, not
bulletproof, acceptable given the low stakes today. Rejected alternative:
manual support-driven entitlement grants in the RevenueCat dashboard — works
at near-zero subscriber counts but doesn't scale, kept as a fallback for
edge cases rather than the primary mechanism.

---

## 5. Repo strategy and v1 support

v2 starts as a **separate git project (or fork of this repo)**, not built
in-place on `main`. v1 keeps shipping and being supported on its own
timeline — current TestFlight users aren't forced onto v2, and v1's
SwiftData-local, single-mode app keeps working exactly as it does today.
The fork point is where v1's iOS/Worker code gets carried over as the
starting skeleton for v2's cloud-backed rewrite; v1's repo continues to
receive its own fixes independently after that point (they diverge).

**Open question:** how long v1 keeps receiving fixes/features once v2 ships,
and whether v1 users get migrated into v2 or simply sunset over time. Not
needed to answer before starting v2, but worth deciding before App Store
submission of v2 (affects whether the v1 listing stays up alongside it).

---

## 6. Closing out v1

Before v2 work displaces attention: finish **game export for v1**
(`docs/lsm-v2-architecture.md` task tracker #1 — CSV export via ShareLink,
two files: game metadata + per-round pick history, designed to also support
a future "import/restore" path). This is the last planned v1 feature; v2
work starts after it lands.
