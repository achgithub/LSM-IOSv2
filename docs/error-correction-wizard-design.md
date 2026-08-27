# Error correction wizard — design plan

**Status: theoretical / not started.** Written up 2026-08-27 after a design
discussion; no code exists yet. This doc is the reference for if/when it gets
built.

## Problem

A manager occasionally closes a round too early — ignoring the incomplete-picks
prompt — and only realizes later that it was their mistake, not a genuinely
missing pick. By the time they notice, a later round (or several) may already
be open and have real picks in it. There is currently no way to correct a
closed round: `GameLogicService.closeRound` mutates `Player.status` in-place
with no per-round audit trail, and `usedTeamIds` reads forward from
closed-round history, so once a later round exists a correction has to
account for both.

## Goals / non-goals

- **Goal:** let a manager retroactively fix one player's pick in one past
  round, and have the consequences (their status, any now-invalid picks in
  later rounds) surface explicitly rather than silently.
- **Goal:** if the game is cloud-synced, push the correction as part of the
  wizard flow, not as a background afterthought.
- **Non-goal:** bulk edits. One player, one correction, one wizard run. This
  is deliberate — see "Design principle: friction is a feature" below.
- **Non-goal:** correcting fixture results. Those are shared across the whole
  round and belong to the existing Results Entry flow.
- **Non-goal:** an audit log / correction history. Andrew: "it's not a
  gambling app and queries will only arrive within a few days of results" —
  not worth the complexity for this use case.
- **Non-goal:** any D1 schema change. Everything below is designed to fit the
  existing `round_pushes` / `round_results` tables unchanged.

## Design principle: friction is a feature

This is explicitly *not* meant to be a fast, forgiving flow. It's a rare,
support-style operation, and the risk isn't a bad tap — it's a manager
skimming past a consequence they should have stopped and looked at. Every
step below that shows a diff or asks for confirmation is there on purpose,
including the type-to-confirm gate. Restricting to one player at a time is
part of this too: if you need to fix two people, you run the wizard twice.

## Flow

1. **Entry point.** Not a first-class button — buried under something like
   League/Game Settings ("Fix a player's history"), so it's discoverable
   when needed but not in the casual navigation path.

2. **Pick the game** (if not already in context).

3. **Pick exactly one player** from that game's roster. No multi-select.

4. **Pick the round to correct**, restricted to closed rounds ≤ the current
   round for that player. Show, pulled from stored data (not guessed):
   - their existing `Pick` for that round (if any) and its `PickResult`
   - their current `Player.status` and which round it was set at
   - why the engine says they're in that state (no pick / result was a
     loss / draw-eliminates rule, etc.)

5. **The correction.** Only this player's *pick* for this round is editable —
   retroactively enter a missing pick, or swap a wrongly-entered one. Fixture
   results are out of scope (see Non-goals).

6. **Forward preview (read-only).** Recompute `GameEngine.computeEliminations`
   forward from the corrected round through the current round, **for this
   player only**, and render a round-by-round diff, e.g.:
   - Round 1: eliminated → survives
   - Round 2: pick "Arsenal" — still valid
   - Round 3: pick "Chelsea" — **team already used elsewhere, now invalid**

   Nothing is applied yet.

7. **Hard stop on unresolved conflicts.** If the forward replay finds a
   now-invalid downstream pick (team-reuse violation, or a pick sitting in a
   round the player was supposed to already be eliminated from), the wizard
   does **not** auto-void or auto-fix it. It blocks progress until the
   manager explicitly resolves each one — enter a replacement pick, or
   explicitly void it. No silent cascading correction.

8. **Type-to-confirm.** Require typing the player's name back, with the full
   diff from step 6 still visible above the input. This is the primary
   "don't make it easy to forget" gate.

9. **Apply locally.** Write the corrected `Pick`, rerun the recompute for
   real, update `Player.status`. Still single-player, single-round-anchor.

10. **Push, blocking.** See "Sync / push design" below. The wizard awaits a
    real success/failure and does not consider itself finished until it sees
    one. On failure: show the failure, offer Retry. No silent local-only
    success when the game is cloud-synced — that's the one outcome worse
    than the wizard refusing to finish.

11. **Done.** No audit trail written (see Non-goals).

## Sync / push design

This is the part that needs new (client + worker) code, but zero schema
changes. Two genuinely different pushes are involved, and conflating them was
the mistake in an earlier version of this design:

### A. Historical correction push (round N, closed)

**Cannot reuse `PWARoundPusher.pushLMSOrPredictor` unmodified.** That
function always builds its "previous results" half from whichever round is
*currently* closed and live (`lmsOrPredictorPreviousResults` /
`killerPreviousResults`), and its own doc comment states it's only safe
because "no round can have closed in between." Worse, it also rewrites the
game's single `round_pushes` row (current round/deadline/eligible-teams) —
so pushing a historical round through it would tell the server round N is
now "current," and reject real players' live submissions for the actually-
open round (`round_moved_on` in `worker-api/src/routes/submissions.ts`).

**What it needs instead:** a new, narrow client function that calls
`SubmissionsClient.pushRound` directly — same endpoint, same wire format —
sending only `previousResultsRoundNumber` + `previousResults` for round N.
On the worker side, `POST /games/:gameToken/push`
(`worker-api/src/routes/submissions.ts:151-274`) needs a leaner branch that:

- does **not** touch `round_pushes` (current-round state stays untouched)
- does **not** run the per-player loop (`game_enrollments`/`player_tokens` —
  those govern live access to the *currently open* round and have nothing
  to do with a closed historical round)
- runs exactly one upsert: `round_results` for round N, full-blob replace
  (this table has no partial-JSON-write pattern anywhere in this codebase —
  `json_set`/`json_patch` etc. are unused — so the blob must contain the
  full corrected round-N results for every player who played that round,
  not just the corrected one; this is a single row write regardless of
  roster size, so it's cheap either way)

This eliminates the `(2N+3)`-query cost of a full snapshot push (1 owner
check + `round_pushes` write + `round_results` write + 2-3 queries per
player) down to ~1-2 D1 operations total. It's a Cloudflare Worker code
change, not a schema change — same `round_results` table and columns, a
narrower code path into it.

### B. Live current-round push (only if the correction changes it)

If the correction changes the *currently open* round's eligible-team pool
(a team freed up, or a team newly blocked for the live round) — per Andrew:
"if the user hasn't submitted a pick like LMS, a change of team choice needs
to be pushed immediately and confirmed during wizard flow." This case
**reuses the existing `pushLMSOrPredictor(round: nil)` unmodified** — it's
built exactly for "current round state," and this is the same cost the app
already accepts on every normal round-open. No new code needed here.

The wizard runs (A) always (if cloud-synced), and (B) conditionally, only
when the recompute in step 6 detects the live pool actually changed.

## Open questions / follow-ups before implementation

- Confirm exact shape of the new worker branch — new route vs. a flag on the
  existing `/push` route — and get it reviewed against
  `worker-api/src/routes/submissions.ts` as it exists at implementation
  time (this doc reflects the code as of 2026-08-27).
- Confirm how "the currently open round's pool changed" is detected cheaply
  from the step-6 recompute output, so (B) isn't triggered unnecessarily.
- No PWA/player-app-side changes are anticipated (the player app just
  receives whatever `round_results`/`round_pushes` state the worker holds),
  but worth a quick check against `docs/pwa-player-app-redesign-brief.md`
  before implementation.
