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

Vite + React + Tailwind PWA (`vite-plugin-pwa`, `injectManifest` strategy).
Deployed as a Cloudflare Pages static build with `functions/s/[token]/manifest.webmanifest.js`
still handling the per-token, per-manager dynamic manifest — that Function is
independent of the Vite build (`manifest: false` in `vite.config.ts`; the
plugin only owns the service worker).

No offline storage — this app is a thin online client of `/s/:token`.

No push notifications — removed (was a half-built scaffold calling
`/s/:token/push/*` routes that never existed on worker-api).

Dev: `npm run dev`. Build: `npm run build` (outputs to `dist/`; deploy with
`wrangler pages deploy dist` run from this directory so `functions/` is
picked up).
