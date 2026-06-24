# LSM Player App (PWA)

The lightweight, **anonymous** web surface players use to submit picks
(LMS mode) or score predictions (Predictor mode). Not tied to either mode — it
renders whatever the player's token says is actionable right now.

## How it works (docs/lsm-v2-architecture.md §3)

1. The manager adds a player in the LSM app, which mints a `submission_tokens`
   row and produces a unique link: `https://<host>/s/<uuid>`.
2. The player opens the link. **No email, no account, no login** — the
   unguessable UUID *is* the credential. This is deliberate: it keeps the player
   side out of GDPR personal-data scope.
3. The PWA calls `GET /s/:token` to fetch what's actionable now (the current
   round's available teams, or this week's fixtures awaiting a score guess) and
   `POST /s/:token` to submit.
4. Submitting writes a `pending` row into `submissions` — it does **not** create
   a real pick/prediction. The manager approves/rejects in the LSM app; approval
   is what makes it live.

## Status

SKELETON. Static shell + a stubbed API client pointing at the v2 Worker's
`/s/:token` endpoints (themselves stubbed — see `worker/src/routes/submissions.ts`).
No build step yet; plain HTML/JS so it can be served from anywhere (Cloudflare
Pages / the existing `web/` host) without tooling.
